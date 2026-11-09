#!/usr/bin/env python3
import getpass
import json
import os
import re
import socket
import subprocess
import sys
from pathlib import Path

from prefect import flow, get_run_logger, task

BASE = Path(os.environ.get("DPE_BASE", "/srv/dpe/sevinch"))
HIVE_HOST = os.environ.get("HIVE_HOST", "team-02-00")
HIVE_PORT = 21050
HIVE_PORTS = (21050, 21051, 21053, 21059)
SPARK_HOME = BASE / "dist" / "spark"
SPARK_SUBMIT = SPARK_HOME / "bin" / "spark-submit"
JOB = BASE / "homeworks" / "hw5" / "jobs" / "spark_sales_summary.py"
CONF_DIR = BASE / "conf" / "hw5"
LOG_DIR = BASE / "logs" / "hw5"
RESULT_DIR = BASE / "homeworks" / "hw5"
SPARK_LOG = LOG_DIR / "spark_submit.log"
VERIFY_FILE = RESULT_DIR / "verify.txt"
RESULT_FILE = RESULT_DIR / "flow_result.json"
SOURCE = "hdfs://team-02-nn:21020/user/dpe_sevinch/hw3/staging/sales.csv"
TABLE = "hw5.sales_summary"
TABLE_PATH = "/user/dpe_sevinch/hive/warehouse/hw5.db/sales_summary"


def spark_env():
    env = os.environ.copy()
    env.update(
        {
            "JAVA_HOME": str(BASE / "dist" / "jdk8"),
            "HADOOP_HOME": str(BASE / "dist" / "hadoop"),
            "HADOOP_CONF_DIR": str(BASE / "conf" / "hw2"),
            "YARN_CONF_DIR": str(BASE / "conf" / "hw2"),
            "HIVE_CONF_DIR": str(CONF_DIR),
            "SPARK_HOME": str(SPARK_HOME),
            "SPARK_CONF_DIR": str(CONF_DIR),
            "SPARK_LOG_DIR": str(LOG_DIR),
            "SPARK_PID_DIR": str(BASE / "pids" / "hw5"),
            "SPARK_LOCAL_DIRS": str(BASE / "tmp" / "hw5"),
            "SPARK_WORKER_DIR": str(BASE / "tmp" / "hw5"),
            "PYSPARK_PYTHON": "/usr/bin/python3",
            "PYSPARK_DRIVER_PYTHON": "/usr/bin/python3",
        }
    )
    env["LD_LIBRARY_PATH"] = (
        str(BASE / "dist" / "hadoop" / "lib" / "native")
        + (":" + env["LD_LIBRARY_PATH"] if env.get("LD_LIBRARY_PATH") else "")
    )
    return env


def run_cmd(cmd, env=None, timeout=600):
    return subprocess.run(
        [str(part) for part in cmd],
        env=env,
        text=True,
        capture_output=True,
        timeout=timeout,
    )


def hdfs_bin():
    return BASE / "dist" / "hadoop" / "bin" / "hdfs"


def yarn_bin():
    return BASE / "dist" / "hadoop" / "bin" / "yarn"


def beeline(sql):
    env = spark_env()
    env["HIVE_CONF_DIR"] = str(BASE / "conf" / "hw3")
    cmd = [
        BASE / "dist" / "hive" / "bin" / "beeline",
        "-u",
        f"jdbc:hive2://{socket.gethostbyname(HIVE_HOST)}:{HIVE_PORT}/default",
        "-n",
        getpass.getuser(),
        "--silent=true",
        "--outputformat=tsv2",
        "-e",
        sql,
    ]
    return run_cmd(cmd, env=env, timeout=180)


def last_int(text):
    values = re.findall(r"^\s*(\d+)\s*$", text, re.MULTILINE)
    return int(values[-1]) if values else None


@task(retries=2, retry_delay_seconds=10, log_prints=True)
def check_cluster():
    logger = get_run_logger()
    env = spark_env()

    report = run_cmd([hdfs_bin(), "dfsadmin", "-report"], env=env, timeout=120)
    live_match = re.search(r"Live datanodes \((\d+)\)", report.stdout)
    live = int(live_match.group(1)) if live_match else 0
    logger.info("HDFS live datanodes: %s", live)
    if live < 3:
        raise RuntimeError("HDFS is not healthy")

    csv_result = run_cmd([hdfs_bin(), "dfs", "-cat", SOURCE], env=env, timeout=120)
    rows = len([line for line in csv_result.stdout.splitlines() if line.strip()])
    logger.info("source rows: %s", rows)
    if rows != 36:
        raise RuntimeError(f"expected 36 source rows, got {rows}")

    nodes = run_cmd([yarn_bin(), "node", "-list"], env=env, timeout=120)
    running = len(re.findall(r"\bRUNNING\b", nodes.stdout))
    logger.info("YARN RUNNING nodes: %s", running)
    if running < 3:
        raise RuntimeError(f"expected 3 RUNNING NodeManagers, got {running}")

    for port in HIVE_PORTS:
        with socket.create_connection((HIVE_HOST, port), timeout=3):
            logger.info("Hive port %s is open", port)

    archive = run_cmd(
        [
            hdfs_bin(),
            "dfs",
            "-test",
            "-e",
            "/user/dpe_sevinch/spark/spark-libs.zip",
        ],
        env=env,
        timeout=60,
    )
    if archive.returncode != 0:
        raise RuntimeError("Spark YARN archive is missing in HDFS")

    return {"live_datanodes": live, "source_rows": rows, "running_nodes": running}


@task(retries=1, retry_delay_seconds=30, log_prints=True)
def run_spark():
    logger = get_run_logger()
    LOG_DIR.mkdir(parents=True, exist_ok=True)
    RESULT_DIR.mkdir(parents=True, exist_ok=True)

    cmd = [
        SPARK_SUBMIT,
        "--master",
        "yarn",
        "--deploy-mode",
        "client",
        "--name",
        "sevinch-hw5-sales-summary",
        "--conf",
        f"spark.hadoop.hive.metastore.uris=thrift://{socket.gethostbyname(HIVE_HOST)}:21053",
        "--conf",
        "spark.ui.port=21405",
        JOB,
        "--source",
        SOURCE,
        "--table",
        TABLE,
    ]
    result = run_cmd(cmd, env=spark_env(), timeout=1800)
    output = result.stdout + "\n" + result.stderr
    SPARK_LOG.write_text(output, encoding="utf-8")
    logger.info("spark-submit exit code: %s", result.returncode)
    logger.info("spark-submit tail:\n%s", "\n".join(output.splitlines()[-25:]))
    if result.returncode != 0:
        raise RuntimeError("spark-submit failed")

    for line in result.stdout.splitlines():
        if line.startswith("HW5_RESULT="):
            return json.loads(line[len("HW5_RESULT=") :])
    raise RuntimeError("HW5_RESULT marker not found in spark-submit output")


@task(retries=2, retry_delay_seconds=10, log_prints=True)
def verify_table(spark_result):
    logger = get_run_logger()
    env = spark_env()
    lines = []
    problems = []

    def add(text):
        lines.append(text)
        logger.info(text)

    add("HW5 Prefect verification")
    add(f"spark_app: {spark_result.get('app_id', 'unknown')}")
    add(f"spark_master: {spark_result.get('master', 'unknown')}")

    tables = beeline("SHOW TABLES IN hw5;")
    add("tables_in_hw5:")
    add(tables.stdout.strip())
    if "sales_summary" not in tables.stdout:
        problems.append("hw5.sales_summary is missing")

    partitions_result = beeline(f"SHOW PARTITIONS {TABLE};")
    partitions = [
        line.strip()
        for line in partitions_result.stdout.splitlines()
        if line.strip().startswith("dt=")
    ]
    add(f"partitions: {len(partitions)}")
    add("\n".join(partitions))
    if len(partitions) != 3:
        problems.append(f"expected 3 partitions, got {len(partitions)}")

    rows_result = beeline(f"SELECT count(*) FROM {TABLE};")
    rows = last_int(rows_result.stdout)
    add(f"rows: {rows}")
    if rows != 9:
        problems.append(f"expected 9 rows, got {rows}")

    days_result = beeline(f"SELECT count(DISTINCT dt) FROM {TABLE};")
    days = last_int(days_result.stdout)
    add(f"days: {days}")
    if days != 3:
        problems.append(f"expected 3 days, got {days}")

    hdfs_result = run_cmd([hdfs_bin(), "dfs", "-ls", TABLE_PATH], env=env, timeout=120)
    hdfs_parts = len(
        [line for line in hdfs_result.stdout.splitlines() if "/dt=" in line]
    )
    add(f"hdfs_partition_dirs: {hdfs_parts}")
    if hdfs_parts != 3:
        problems.append(f"expected 3 HDFS partition dirs, got {hdfs_parts}")

    aggregates = beeline(
        f"SELECT dt, sum(orders), round(sum(total_amount), 2) "
        f"FROM {TABLE} GROUP BY dt ORDER BY dt;"
    )
    add("aggregates_by_day:")
    add(aggregates.stdout.strip())

    describe = beeline(
        f"SET hive.fetch.task.conversion=more; DESCRIBE FORMATTED {TABLE};"
    )
    add("table_metadata:")
    add(
        "\n".join(
            line
            for line in describe.stdout.splitlines()
            if any(
                key in line
                for key in ("Table Type", "Location", "Partition", "dt")
            )
        )
    )

    lines.append("")
    if problems:
        lines.append("VERIFY: FAIL")
        lines.extend(problems)
    else:
        lines.append("VERIFY: OK")

    VERIFY_FILE.write_text("\n".join(lines) + "\n", encoding="utf-8")
    if problems:
        raise RuntimeError("; ".join(problems))

    return {
        "rows": rows,
        "days": days,
        "partitions": partitions,
        "hdfs_partitions": hdfs_parts,
        "verified": True,
    }


@flow(name="sevinch-hw5-sales-pipeline", log_prints=True, timeout_seconds=3600)
def sales_pipeline():
    cluster = check_cluster()
    spark_result = run_spark()
    verification = verify_table(spark_result)
    result = {
        "cluster": cluster,
        "spark": spark_result,
        "verify": verification,
    }
    RESULT_DIR.mkdir(parents=True, exist_ok=True)
    RESULT_FILE.write_text(
        json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    return result


if __name__ == "__main__":
    try:
        flow_result = sales_pipeline()
        print(
            "HW5_FLOW_RESULT=" + json.dumps(flow_result, sort_keys=True),
            flush=True,
        )
    except Exception as exc:
        print(f"HW5_FLOW_ERROR: {exc}", file=sys.stderr, flush=True)
        raise
