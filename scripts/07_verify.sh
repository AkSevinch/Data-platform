#!/usr/bin/env bash
# 07_verify.sh
# Проверка целостности кластера HDFS.
# - hdfs dfsadmin -report: 3 живых DataNode, Decommission Status = Normal;
# - недостаточная репликация/недостающие/коррумпированные блоки = 0;
# - веб-интерфейс NameNode отвечает HTTP 200;
# - в логах нет критических ошибок;
# - функциональный тест записи/чтения.
# Выполнять с edge-ноды от пользователя team.
set -euo pipefail

nn() { # nn <script> — выполнить на team-02-nn от dpe_sevinch
  ssh -i ~/.ssh/team_internal -o ConnectTimeout=8 "team@team-02-nn" \
    "sudo -iu dpe_sevinch bash -s" <<< "$1"
}

echo "===== 1. dfsadmin -report (ожидаем 3 live datanodes) ====="
nn 'source ~/.dpe_env; hdfs dfsadmin -report' \
  | grep -E "Live datanodes|Name:|Decommission Status|Under replicated|corrupt|Missing blocks"

echo
echo "===== 2. Веб-интерфейс NameNode ====="
ssh -i ~/.ssh/team_internal -o ConnectTimeout=8 team@team-02-nn \
  "curl -s -L -m 10 -o /dev/null -w 'HTTP %{http_code} -> %{url_effective}\n' http://10.2.0.11:21970/"

echo
echo "===== 3. Критические ошибки в логах ====="
for HOST in team-02-nn team-02-00 team-02-01; do
  echo "-- $HOST --"
  ssh -i ~/.ssh/team_internal -o ConnectTimeout=8 "team@$HOST" \
    "sudo -iu dpe_sevinch bash -s" <<'LOGS'
source ~/.dpe_env
found=0
for f in "$HADOOP_LOG_DIR"/*.log "$HADOOP_LOG_DIR"/*.out; do
  [ -f "$f" ] || continue
  found=1
  echo "  $(basename "$f"): ERROR/FATAL=$(grep -cE 'ERROR|FATAL' "$f")"
done
[ "$found" = 1 ] || echo "  (нет файлов логов)"
LOGS
done

echo
echo "===== 4. Функциональный тест записи/чтения ====="
nn '
source ~/.dpe_env
hdfs dfs -mkdir -p /user/dpe_sevinch/hw1
echo "verify-test-$(date +%s)" > "$DPE_TMP_DIR/verify.txt"
hdfs dfs -put -f "$DPE_TMP_DIR/verify.txt" /user/dpe_sevinch/hw1/verify.txt
hdfs fsck /user/dpe_sevinch/hw1/verify.txt -files -blocks 2>&1 | grep -E "replicated|HEALTHY|Status"
hdfs dfs -cat /user/dpe_sevinch/hw1/verify.txt
'
echo
echo "DONE"