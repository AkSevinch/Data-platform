#!/usr/bin/env bash
set -euo pipefail

LINUX_USER="dpe_sevinch"
HIVE_HOST="team-02-00"

HIVE_IP=$(getent ahostsv4 "$HIVE_HOST" | awk 'NR==1{print $1}')
[ -n "$HIVE_IP" ] || { echo "не удалось определить IP для $HIVE_HOST"; exit 1; }

echo "--> $HIVE_HOST (остановка Hive)"
ssh -i ~/.ssh/team_internal -o ConnectTimeout=8 \
  "team@$HIVE_HOST" "sudo -iu $LINUX_USER env HIVE_IP=$HIVE_IP bash -s" <<'EOF'
set -euo pipefail
source ~/.dpe_env
source "$DPE_BASE/conf/hw3/hive-env.sh"

PIDS="$DPE_BASE/pids/hw3"
LOGS="$DPE_BASE/logs/hw3"

stop_pattern() {
  local pat="$1"
  local pids
  pids=$(ps -u "$(id -un)" -o pid=,cmd= | grep -E "$pat" | grep -v grep | awk '{print $1}' || true)
  if [ -n "$pids" ]; then
    echo "  TERM $pat: $pids"
    kill $pids 2>/dev/null || true
  fi
}

stop_pattern 'HiveServer2'
stop_pattern 'HiveMetaStore'

for i in $(seq 1 20); do
  n=$(ps -u "$(id -un)" -o cmd= | grep -cE 'HiveServer2|HiveMetaStore' || true)
  [ "$n" -eq 0 ] && break
  sleep 1
done

DERBY_HOME="$DPE_BASE/dist/derby"
DERBY_CP="$DERBY_HOME/lib/derby.jar:$DERBY_HOME/lib/derbynet.jar:$DERBY_HOME/lib/derbytools.jar"
if ss -ltn 2>/dev/null | grep -q ":21059 "; then
  echo "  shutdown Derby network server"
  "$JAVA_HOME/bin/java" -cp "$DERBY_CP" org.apache.derby.drda.NetworkServerControl \
    shutdown -h "$HIVE_IP" -p 21059 >/dev/null 2>&1 || true
fi

for i in $(seq 1 20); do
  c=$(ss -ltn 2>/dev/null | grep -cE ':21050 |:21051 |:21053 |:21059 ' || true)
  [ "$c" -eq 0 ] && break
  sleep 1
done

rm -f "$PIDS"/derby.pid "$PIDS"/metastore.pid "$PIDS"/hiveserver2.pid

mkdir -p "$LOGS/prev"
for f in "$LOGS"/*.out "$LOGS"/*.log; do
  [ -f "$f" ] && mv "$f" "$LOGS/prev/" || true
done

echo "  остались процессы Hive?"
ps -u "$(id -un)" -o pid=,cmd= | grep -E 'HiveServer2|HiveMetaStore|NetworkServerControl' | grep -v grep || echo "  none"
echo "  остались порты Hive?"
ss -ltn 2>/dev/null | grep -E ':21050 |:21051 |:21053 |:21059 ' || echo "  none"
EOF

echo "DONE (YARN и HDFS не тронуты)"
