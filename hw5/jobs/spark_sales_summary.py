#!/usr/bin/env python3
import argparse
import json
import re
import sys

from pyspark.sql import SparkSession
from pyspark.sql import functions as F


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--source",
        default="hdfs://team-02-nn:21020/user/dpe_sevinch/hw3/staging/sales.csv",
    )
    parser.add_argument("--table", default="hw5.sales_summary")
    return parser.parse_args()


def main():
    args = parse_args()
    if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*\.[A-Za-z_][A-Za-z0-9_]*", args.table):
        raise ValueError("invalid table name")

    spark = (
        SparkSession.builder.appName("sevinch-hw5-sales-summary")
        .enableHiveSupport()
        .getOrCreate()
    )
    spark.sparkContext.setLogLevel("WARN")

    try:
        spark.sql("CREATE DATABASE IF NOT EXISTS hw5")
        spark.sql("SET hive.exec.dynamic.partition.mode=nonstrict")
        spark.sql(f"DROP TABLE IF EXISTS {args.table}")

        raw = spark.read.option("header", "false").csv(args.source)
        clean = (
            raw.select(
                F.col("_c0").cast("int").alias("id"),
                F.col("_c1").alias("category"),
                F.col("_c2").cast("decimal(12,2)").alias("amount"),
                F.to_date(F.col("_c3"), "yyyy-MM-dd").alias("sale_date"),
                F.col("_c3").alias("dt"),
            )
            .where(F.col("amount") > 0)
        )

        summary = clean.groupBy("sale_date", "category", "dt").agg(
            F.count("*").alias("orders"),
            F.round(F.sum("amount"), 2).cast("decimal(12,2)").alias("total_amount"),
            F.round(F.avg("amount"), 2).cast("decimal(12,2)").alias("avg_amount"),
            F.round(F.max("amount"), 2).cast("decimal(12,2)").alias("max_amount"),
        )

        summary.write.mode("overwrite").partitionBy("dt").format("parquet").saveAsTable(
            args.table
        )
        spark.sql(f"REFRESH TABLE {args.table}")

        result = {
            "app_id": spark.sparkContext.applicationId,
            "master": spark.sparkContext.master,
            "source": args.source,
            "table": args.table,
            "rows": spark.table(args.table).count(),
            "partitions": [
                row[0] for row in spark.sql(f"SHOW PARTITIONS {args.table}").collect()
            ],
            "days": spark.sql(
                f"SELECT count(DISTINCT dt) AS days FROM {args.table}"
            ).collect()[0]["days"],
        }
        print("HW5_RESULT=" + json.dumps(result, sort_keys=True), flush=True)
    finally:
        spark.stop()


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(f"HW5_ERROR: {exc}", file=sys.stderr, flush=True)
        raise
