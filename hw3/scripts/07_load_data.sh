#!/usr/bin/env bash
set -euo pipefail

LINUX_USER="dpe_sevinch"
HIVE_HOST="team-02-00"

HIVE_IP=$(getent ahostsv4 "$HIVE_HOST" | awk 'NR==1{print $1}')
[ -n "$HIVE_IP" ] || { echo "не удалось определить IP для $HIVE_HOST"; exit 1; }

echo "--> $HIVE_HOST (данные и партиционированная таблица)"
ssh -i ~/.ssh/team_internal -o ConnectTimeout=8 \
  "team@$HIVE_HOST" "sudo -iu $LINUX_USER env HIVE_IP=$HIVE_IP bash -s" <<'EOF'
set -euo pipefail
source ~/.dpe_env
source "$DPE_BASE/conf/hw3/hive-env.sh"

CSV=/tmp/hw3_sales.csv
SQL=/tmp/hw3_load.sql
LOG="$DPE_BASE/logs/hw3/load_data.log"
RESULT="$DPE_BASE/homeworks/hw3/load_result.txt"
BEELINE="$HIVE_HOME/bin/beeline -u jdbc:hive2://$HIVE_IP:21050/default -n $(id -un) --silent=true"

{
  id=1
  for dt in 2026-10-20 2026-10-21 2026-10-22; do
    for c in books food tech; do
      for i in 1 2 3 4; do
        amount=$(( (id * 37) % 90 + 10 ))
        echo "$id,$c,$amount.50,$dt"
        id=$((id + 1))
      done
    done
  done
} > "$CSV"

export HADOOP_CONF_DIR="$DPE_BASE/conf/hw2"
hdfs dfs -rm -r -f /user/dpe_sevinch/hw3/staging >/dev/null 2>&1 || true
hdfs dfs -mkdir -p /user/dpe_sevinch/hw3/staging
hdfs dfs -put -f "$CSV" /user/dpe_sevinch/hw3/staging/sales.csv
hdfs dfs -rm -r -f /user/dpe_sevinch/hive/warehouse/hw3.db/sales_part >/dev/null 2>&1 || true
hdfs dfs -ls /user/dpe_sevinch/hw3/staging

cat > "$SQL" <<'SQL'
CREATE DATABASE IF NOT EXISTS hw3;
DROP TABLE IF EXISTS hw3.sales_staging;
CREATE EXTERNAL TABLE hw3.sales_staging (
  id INT,
  category STRING,
  amount DOUBLE,
  dt STRING
)
ROW FORMAT DELIMITED FIELDS TERMINATED BY ','
STORED AS TEXTFILE
LOCATION 'hdfs://team-02-nn:21020/user/dpe_sevinch/hw3/staging';

DROP TABLE IF EXISTS hw3.sales_part;
CREATE TABLE hw3.sales_part (
  id INT,
  category STRING,
  amount DOUBLE
)
PARTITIONED BY (dt STRING)
STORED AS ORC;

SET hive.exec.dynamic.partition=true;
SET hive.exec.dynamic.partition.mode=nonstrict;
SET hive.exec.max.dynamic.partitions=1000;
SET hive.exec.max.dynamic.partitions.pernode=200;
SET hive.vectorized.execution.enabled=false;
SET hive.vectorized.execution.reduce.enabled=false;
SET mapreduce.map.memory.mb=512;
SET mapreduce.map.java.opts=-Xmx384m;
SET mapreduce.reduce.memory.mb=512;
SET mapreduce.reduce.java.opts=-Xmx384m;
SET yarn.app.mapreduce.am.resource.mb=512;
SET yarn.app.mapreduce.am.command-opts=-Xmx384m;
SET mapreduce.job.reduces=1;

INSERT OVERWRITE TABLE hw3.sales_part PARTITION(dt)
SELECT id, category, amount, dt FROM hw3.sales_staging;

SHOW PARTITIONS hw3.sales_part;
SELECT dt, count(*) AS cnt, round(sum(amount), 2) AS total
FROM hw3.sales_part GROUP BY dt ORDER BY dt;
SELECT count(*) AS total_rows FROM hw3.sales_part;
SQL

if ! $BEELINE -f "$SQL" > "$LOG" 2>&1; then
  echo "  загрузка упала"; tail -60 "$LOG"; exit 1
fi
tail -30 "$LOG"

PARTS=$($BEELINE --outputformat=tsv2 -e "SHOW PARTITIONS hw3.sales_part;" 2>/dev/null | grep -c '^dt=' || true)
ROWS=$($BEELINE --outputformat=tsv2 -e "SELECT count(*) FROM hw3.sales_part;" 2>/dev/null | grep -E '^[0-9]+$' | tail -1 || true)
HDFS_PARTS=$(hdfs dfs -ls /user/dpe_sevinch/hive/warehouse/hw3.db/sales_part 2>/dev/null | grep -c 'dt=' || true)

{
  echo "partitions: $PARTS"
  echo "hdfs partition dirs: $HDFS_PARTS"
  echo "rows: ${ROWS:-unknown}"
  echo
  echo "show partitions:"
  $BEELINE -e "SHOW PARTITIONS hw3.sales_part;" 2>/dev/null
  echo
  echo "counts by dt:"
  $BEELINE --outputformat=tsv2 -e "SELECT dt, count(*), round(sum(amount),2) FROM hw3.sales_part GROUP BY dt ORDER BY dt;" 2>/dev/null
} | tee "$RESULT"

[ "$PARTS" -eq 3 ] || { echo "  ожидались 3 партиции, получено $PARTS"; exit 1; }
[ "$HDFS_PARTS" -eq 3 ] || { echo "  в HDFS не 3 каталога партиций"; exit 1; }
[ "${ROWS:-0}" -eq 36 ] || { echo "  ожидалось 36 строк, получено ${ROWS:-unknown}"; exit 1; }

echo "  загрузка и партиционирование OK"
EOF

echo "DONE"
