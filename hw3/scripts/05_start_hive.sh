#!/usr/bin/env bash
set -euo pipefail

LINUX_USER="dpe_sevinch"
HIVE_HOST="team-02-00"

HIVE_IP=$(getent ahostsv4 "$HIVE_HOST" | awk 'NR==1{print $1}')
[ -n "$HIVE_IP" ] || { echo "не удалось определить IP для $HIVE_HOST"; exit 1; }

echo "--> $HIVE_HOST (Derby + Metastore + HiveServer2)"
ssh -i ~/.ssh/team_internal -o ConnectTimeout=8 \
  "team@$HIVE_HOST" "sudo -iu $LINUX_USER env HIVE_IP=$HIVE_IP bash -s" <<'EOF'
set -euo pipefail
source ~/.dpe_env
source "$DPE_BASE/conf/hw3/hive-env.sh"

DERBY_HOME="$DPE_BASE/dist/derby"
DERBY_CP="$DERBY_HOME/lib/derby.jar:$DERBY_HOME/lib/derbynet.jar:$DERBY_HOME/lib/derbytools.jar"
LOGS="$DPE_BASE/logs/hw3"
PIDS="$DPE_BASE/pids/hw3"

port_up() { ss -ltn 2>/dev/null | grep -q ":$1 "; }

if ! port_up 21059; then
  echo "  запуск Derby"
  nohup "$JAVA_HOME/bin/java" -Xmx192m \
    -Dderby.system.home="$DPE_BASE/data/hw3/derby" \
    -Dderby.stream.error.file="$LOGS/derby-error.log" \
    -cp "$DERBY_CP" org.apache.derby.drda.NetworkServerControl start \
    -h "$HIVE_IP" -p 21059 > "$LOGS/derby.out" 2>&1 &
  echo $! > "$PIDS/derby.pid"
fi
for i in $(seq 1 30); do port_up 21059 && break; sleep 1; done
port_up 21059 || { echo "  Derby не поднялся"; tail -20 "$LOGS/derby.out" || true; exit 1; }
echo "  Derby: 21059"

if ! port_up 21053; then
  echo "  запуск Hive Metastore"
  nohup "$HIVE_HOME/bin/hive" --service metastore > "$LOGS/metastore.out" 2>&1 &
  echo $! > "$PIDS/metastore.pid"
  ok=0
  for i in $(seq 1 60); do
    port_up 21053 && { ok=1; break; }
    kill -0 "$(cat "$PIDS/metastore.pid")" 2>/dev/null || break
    sleep 1
  done
  [ "$ok" = 1 ] || { echo "  Metastore не поднялся"; tail -40 "$LOGS/metastore.out"; exit 1; }
fi
echo "  Metastore: 21053"

if ! port_up 21050; then
  echo "  запуск HiveServer2"
  nohup "$HIVE_HOME/bin/hive" --service hiveserver2 > "$LOGS/hiveserver2.out" 2>&1 &
  echo $! > "$PIDS/hiveserver2.pid"
  ok=0
  for i in $(seq 1 90); do
    if port_up 21050 && port_up 21051; then ok=1; break; fi
    kill -0 "$(cat "$PIDS/hiveserver2.pid")" 2>/dev/null || break
    sleep 1
  done
  [ "$ok" = 1 ] || { echo "  HiveServer2 не поднялся"; tail -50 "$LOGS/hiveserver2.out"; exit 1; }
fi
echo "  HiveServer2: 21050, web UI 21051"

for f in derby metastore hiveserver2; do
  [ -f "$PIDS/$f.pid" ] && echo "  $f pid: $(cat "$PIDS/$f.pid")"
done
ps -u "$(id -un)" -o pid=,cmd= | grep -E 'NetworkServerControl|HiveMetaStore|HiveServer2' | grep -v grep || true
EOF

echo "DONE. Проверка: bash hw3/scripts/06_verify.sh"
