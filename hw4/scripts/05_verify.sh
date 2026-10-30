#!/usr/bin/env bash
set -euo pipefail

NAME="sevinch"
LINUX_USER="dpe_sevinch"
BASE="/srv/dpe/$NAME"
DRIVER_HOST="team-02-nn"

echo "--> $DRIVER_HOST (проверка hw4.sales_summary)"
ssh -i ~/.ssh/team_internal -o ConnectTimeout=8 "team@$DRIVER_HOST" \
  "sudo -iu $LINUX_USER bash -s" <<'EOF'
set -euo pipefail
source ~/.dpe_env
export HADOOP_CONF_DIR="$DPE_BASE/conf/hw2"
export HIVE_CONF_DIR="$DPE_BASE/conf/hw3"

HIVE_HOME="$DPE_BASE/dist/hive"
HIVE_IP=$(getent ahostsv4 team-02-00 | awk 'NR==1{print $1}')
[ -n "$HIVE_IP" ] || { echo "не удалось определить IP Hive"; exit 1; }
TABLE_PATH="/user/dpe_sevinch/hive/warehouse/hw4.db/sales_summary"
OUT="$DPE_BASE/homeworks/hw4/verify.txt"
FAILED=0
: > "$OUT"

beeline_run() {
  "$HIVE_HOME/bin/beeline" -u "jdbc:hive2://$HIVE_IP:21050/default" \
    -n "$(id -un)" --silent=true "$@"
}
tsv() {
  beeline_run --outputformat=tsv2 "$@"
}

echo "1. режим создания таблицы" | tee -a "$OUT"
MODE=$(cat "$DPE_BASE/homeworks/hw4/mode.txt" 2>/dev/null || echo unknown)
echo "   mode: $MODE" | tee -a "$OUT"

echo "2. HDFS-каталог таблицы" | tee -a "$OUT"
hdfs dfs -ls -h "$TABLE_PATH" 2>&1 | tee -a "$OUT" || {
  echo "   каталог таблицы не найден" | tee -a "$OUT"; FAILED=1;
}
HDFS_PARTS=$(hdfs dfs -ls "$TABLE_PATH" 2>/dev/null | grep -c 'dt=' || true)
echo "   HDFS partition dirs: $HDFS_PARTS" | tee -a "$OUT"
[ "$HDFS_PARTS" -eq 3 ] || { echo "   ожидались 3 каталога dt=" | tee -a "$OUT"; FAILED=1; }

echo "3. таблица в metastore" | tee -a "$OUT"
TABLES=$(tsv -e "SHOW TABLES IN hw4;" 2>/dev/null || true)
echo "$TABLES" | tee -a "$OUT"
echo "$TABLES" | grep -q 'sales_summary' || {
  echo "   hw4.sales_summary не найдена" | tee -a "$OUT"; FAILED=1;
}

echo "4. партиции" | tee -a "$OUT"
PARTITIONS=$(tsv -e "SHOW PARTITIONS hw4.sales_summary;" 2>/dev/null || true)
echo "$PARTITIONS" | tee -a "$OUT"
PARTS=$(echo "$PARTITIONS" | grep -c 'dt=' || true)
echo "   partitions: $PARTS" | tee -a "$OUT"
[ "$PARTS" -eq 3 ] || { echo "   ожидались 3 партиции" | tee -a "$OUT"; FAILED=1; }
if echo "$PARTITIONS" | grep -q 'dt=dt'; then
  echo "   найден ошибочный dt=dt" | tee -a "$OUT"; FAILED=1;
fi

echo "5. количество строк и дней" | tee -a "$OUT"
ROWS=$(tsv -e "SELECT count(*) FROM hw4.sales_summary;" 2>/dev/null | grep -E '^[0-9]+$' | tail -1 || true)
DAYS=$(tsv -e "SELECT count(DISTINCT dt) FROM hw4.sales_summary;" 2>/dev/null | grep -E '^[0-9]+$' | tail -1 || true)
echo "   rows: ${ROWS:-unknown}" | tee -a "$OUT"
echo "   days: ${DAYS:-unknown}" | tee -a "$OUT"
[ "${ROWS:-0}" -eq 9 ] || { echo "   ожидалось 9 строк" | tee -a "$OUT"; FAILED=1; }
[ "${DAYS:-0}" -eq 3 ] || { echo "   ожидалось 3 дня" | tee -a "$OUT"; FAILED=1; }

echo "6. агрегаты по дням" | tee -a "$OUT"
tsv -e "SELECT dt, sum(orders), round(sum(total_amount), 2) FROM hw4.sales_summary GROUP BY dt ORDER BY dt;" 2>/dev/null | tee -a "$OUT" || {
  echo "   агрегаты не выполнились" | tee -a "$OUT"; FAILED=1;
}

echo "7. содержимое таблицы" | tee -a "$OUT"
tsv -e "SET hive.fetch.task.conversion=more; SELECT dt, sale_date, category, orders, total_amount, avg_amount, max_amount FROM hw4.sales_summary;" 2>/dev/null | tee -a "$OUT" || {
  echo "   SELECT * не выполнился" | tee -a "$OUT"; FAILED=1;
}

echo "8. описание таблицы" | tee -a "$OUT"
beeline_run -e "DESCRIBE FORMATTED hw4.sales_summary;" 2>/dev/null | grep -E 'Table Type|Location|Partition|dt' | tee -a "$OUT" || true

echo | tee -a "$OUT"
if [ "$FAILED" = 0 ]; then
  echo "VERIFY: OK" | tee -a "$OUT"
else
  echo "VERIFY: FAIL" | tee -a "$OUT"
  exit 1
fi
EOF

echo "DONE"
