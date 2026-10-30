#!/usr/bin/env bash
set -euo pipefail

NAME="sevinch"
LINUX_USER="dpe_sevinch"
BASE="/srv/dpe/$NAME"
DRIVER_HOST="team-02-nn"
JOBS_DIR="$(cd "$(dirname "$0")/../jobs" && pwd)"

echo "--> $DRIVER_HOST (копирование SQL-заданий)"
ssh -i ~/.ssh/team_internal -o ConnectTimeout=8 "team@$DRIVER_HOST" \
  "rm -rf /tmp/hw4_jobs && mkdir -p /tmp/hw4_jobs"
scp -q -i ~/.ssh/team_internal -o StrictHostKeyChecking=accept-new \
  "$JOBS_DIR"/*.sql "team@$DRIVER_HOST:/tmp/hw4_jobs/"
ssh -i ~/.ssh/team_internal -o ConnectTimeout=8 "team@$DRIVER_HOST" "
  set -e
  sudo mkdir -p '$BASE/homeworks/hw4/jobs'
  sudo cp /tmp/hw4_jobs/*.sql '$BASE/homeworks/hw4/jobs/'
  sudo chown -R $LINUX_USER:$LINUX_USER '$BASE/homeworks/hw4/jobs'
  sudo rm -rf /tmp/hw4_jobs
"

echo "--> $DRIVER_HOST (Spark SQL на YARN)"
ssh -i ~/.ssh/team_internal -o ConnectTimeout=8 "team@$DRIVER_HOST" \
  "sudo -iu $LINUX_USER bash -s" <<'EOF'
set -euo pipefail
source ~/.dpe_env
export SPARK_HOME="$DPE_BASE/dist/spark"
export SPARK_CONF_DIR="$DPE_BASE/conf/hw4"
source "$SPARK_CONF_DIR/spark-env.sh"

JOBS="$DPE_BASE/homeworks/hw4/jobs"
LOGS="$DPE_BASE/logs/hw4"
SPARK_SQL="$SPARK_HOME/bin/spark-sql"
HIVE_HOME="$DPE_BASE/dist/hive"
HIVE_IP=$(getent ahostsv4 team-02-00 | awk 'NR==1{print $1}')
[ -n "$HIVE_IP" ] || { echo "не удалось определить IP Hive"; exit 1; }

beeline_run() {
  HIVE_CONF_DIR="$DPE_BASE/conf/hw3" \
    "$HIVE_HOME/bin/beeline" -u "jdbc:hive2://$HIVE_IP:21050/default" \
    -n "$(id -un)" --silent=true "$@"
}

CTAS_LOG="$LOGS/spark_ctas.log"
PARQUET_LOG="$LOGS/spark_parquet.log"
DDL_LOG="$LOGS/hive_ddl.log"
MODE_FILE="$DPE_BASE/homeworks/hw4/mode.txt"
: > "$CTAS_LOG"
: > "$PARQUET_LOG"
: > "$DDL_LOG"

echo "  CTAS: hw4.sales_summary"
if "$SPARK_SQL" --master yarn --deploy-mode client \
  --conf spark.app.name=sevinch-hw4-sales-summary \
  -f "$JOBS/01_sales_summary_ctas.sql" > "$CTAS_LOG" 2>&1; then
  MODE="spark_ctas"
  echo "  CTAS успешно"
else
  echo "  CTAS не удался, смотрю лог:"
  tail -60 "$CTAS_LOG" || true
  echo "  fallback: Spark пишет партиционированный Parquet"

  if ! "$SPARK_SQL" --master yarn --deploy-mode client \
    --conf spark.app.name=sevinch-hw4-sales-summary-parquet \
    --conf spark.sql.catalogImplementation=in-memory \
    -f "$JOBS/02_sales_summary_parquet.sql" > "$PARQUET_LOG" 2>&1; then
    echo "  Parquet fallback тоже не удался:"
    tail -60 "$PARQUET_LOG" || true
    exit 1
  fi

  echo "  Hive DDL для external table"
  if ! beeline_run -f "$JOBS/03_create_external_table.sql" > "$DDL_LOG" 2>&1; then
    echo "  Hive DDL не удался:"
    tail -60 "$DDL_LOG" || true
    exit 1
  fi
  MODE="external_parquet"
fi

echo "$MODE" > "$MODE_FILE"
echo "MODE: $MODE"
echo "  лог CTAS: $CTAS_LOG"
if [ -s "$PARQUET_LOG" ]; then echo "  лог Parquet: $PARQUET_LOG"; fi
if [ -s "$DDL_LOG" ]; then echo "  лог Hive DDL: $DDL_LOG"; fi
EOF

echo "DONE"
