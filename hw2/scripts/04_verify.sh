#!/usr/bin/env bash
set -euo pipefail

NODES=("team-02-nn" "team-02-00" "team-02-01")
YARN_PORTS_BY_NODE=(
  "team-02-nn:21040 21041 21042 21045 21030 21031 21032 21033 21088 21120 21888 21188"
  "team-02-00:21040 21041 21042 21045"
  "team-02-01:21040 21041 21042 21045"
)

nn() { # выполнить команду на team-02-nn от dpe_sevinch с конфигами hw2
  ssh -i ~/.ssh/team_internal -o ConnectTimeout=8 "team@team-02-nn" \
    "sudo -iu dpe_sevinch bash -s" <<< "source ~/.dpe_env
export HADOOP_CONF_DIR=/srv/dpe/sevinch/conf/hw2
export HADOOP_LOG_DIR=/srv/dpe/sevinch/logs/hw2
export HADOOP_PID_DIR=/srv/dpe/sevinch/pids/hw2
export HADOOP_TMP_DIR=/srv/dpe/sevinch/tmp/hw2
$1"
}

echo "1. процессы YARN (только dpe_sevinch)"
for HOST in "${NODES[@]}"; do
  echo "--> $HOST"
  ssh -i ~/.ssh/team_internal -o ConnectTimeout=8 "team@$HOST" \
    "ps -eo user,cmd | grep dpe_sevinch | grep -oE 'Dproc_(resourcemanager|nodemanager|historyserver|timelineserver)' | sort -u || true"
done

echo
echo "2. порты YARN"
for ENTRY in "${YARN_PORTS_BY_NODE[@]}"; do
  HOST="${ENTRY%%:*}"
  PORTS="${ENTRY#*:}"
  echo "--> $HOST"
  ssh -i ~/.ssh/team_internal -o ConnectTimeout=8 "team@$HOST" \
    "for p in $PORTS; do ss -ltn | grep -q \":\$p \" && echo \"  :\$p LISTEN\" || echo \"  :\$p MISSING\"; done"
done

echo
echo "3. ноды и приложения YARN (ожидаем 3 RUNNING)"
nn 'yarn node -list 2>/dev/null | grep -E "Node-Id|RUNNING"'
nn 'yarn application -list 2>/dev/null | head -5 || true'

echo
echo "4. тестовый MapReduce job (pi)"
nn 'hadoop jar /srv/dpe/sevinch/dist/hadoop/share/hadoop/mapreduce/hadoop-mapreduce-examples-3.3.6.jar pi 2 10 2>&1 | grep -E "Estimated|JobId|completed successfully" || true'

echo
echo "5. веб-интерфейсы всех демонов"
check_ui() { # check_ui <host> <port> <name>
  CODE=$(curl -s -L -m 8 -o /dev/null -w '%{http_code}' "http://$1:$2/" || echo 000)
  if [ "$CODE" = "200" ] || [ "$CODE" = "302" ]; then
    echo "  HTTP $CODE  $3  http://$1:$2/"
  else
    echo "  FAIL($CODE) $3  http://$1:$2/"
    FAILED=1
  fi
}
FAILED=0
check_ui 10.2.0.11 21970 "NameNode"
check_ui 10.2.0.11 21968 "SecondaryNameNode"
check_ui 10.2.0.11 21964 "DataNode-11"
check_ui 10.2.0.12 21964 "DataNode-12"
check_ui 10.2.0.13 21964 "DataNode-13"
check_ui 10.2.0.11 21088 "ResourceManager"
check_ui 10.2.0.11 21042 "NodeManager-11"
check_ui 10.2.0.12 21042 "NodeManager-12"
check_ui 10.2.0.13 21042 "NodeManager-13"
check_ui 10.2.0.11 21888 "JobHistory"
check_ui 10.2.0.11 21188 "Timeline"

echo
echo "6. критические ошибки в логах hw2"
for HOST in "${NODES[@]}"; do
  echo "--> $HOST"
  ssh -i ~/.ssh/team_internal -o ConnectTimeout=8 "team@$HOST" \
    "sudo -iu dpe_sevinch bash -s" <<'LOGS'
source ~/.dpe_env
L=/srv/dpe/sevinch/logs/hw2
found=0
for f in "$L"/*.log "$L"/*.out; do
  [ -f "$f" ] || continue
  found=1
  echo "  $(basename "$f"): ERROR/FATAL=$(grep -E 'ERROR|FATAL' "$f" | grep -vE 'RECEIVED SIGNAL 15: SIGTERM|InterruptedException' | wc -l)"
done
[ "$found" = 1 ] || echo "  (нет файлов логов)"
LOGS
done

echo
if [ "$FAILED" = 1 ]; then
  echo "ЕСТЬ FAIL по UI — см шаг 5"
  exit 1
fi
echo "DONE"
