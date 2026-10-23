#!/usr/bin/env bash
set -euo pipefail

LINUX_USER="dpe_sevinch"
HIVE_HOST="team-02-00"

HIVE_IP=$(getent ahostsv4 "$HIVE_HOST" | awk 'NR==1{print $1}')
[ -n "$HIVE_IP" ] || { echo "не удалось определить IP для $HIVE_HOST"; exit 1; }

echo "--> $HIVE_HOST (Derby network server + metastore schema)"
ssh -i ~/.ssh/team_internal -o ConnectTimeout=8 \
  "team@$HIVE_HOST" "sudo -iu $LINUX_USER env HIVE_IP=$HIVE_IP bash -s" <<'EOF'
set -euo pipefail
source ~/.dpe_env
source "$DPE_BASE/conf/hw3/hive-env.sh"

DERBY_HOME="$DPE_BASE/dist/derby"
DERBY_CP="$DERBY_HOME/lib/derby.jar:$DERBY_HOME/lib/derbynet.jar:$DERBY_HOME/lib/derbytools.jar"
LOG="$DPE_BASE/logs/hw3/schema_tool.log"

if ! ss -ltn 2>/dev/null | grep -q ":21059 "; then
  nohup "$JAVA_HOME/bin/java" -Xmx192m \
    -Dderby.system.home="$DPE_BASE/data/hw3/derby" \
    -Dderby.stream.error.file="$DPE_BASE/logs/hw3/derby-error.log" \
    -cp "$DERBY_CP" org.apache.derby.drda.NetworkServerControl start \
    -h "$HIVE_IP" -p 21059 > "$DPE_BASE/logs/hw3/derby.out" 2>&1 &
  echo $! > "$DPE_BASE/pids/hw3/derby.pid"
fi

ok=0
for i in $(seq 1 30); do
  if ss -ltn 2>/dev/null | grep -q ":21059 "; then ok=1; break; fi
  sleep 1
done
[ "$ok" = 1 ] || { echo "Derby не поднялся"; tail -20 "$DPE_BASE/logs/hw3/derby.out" || true; exit 1; }
echo "  Derby слушает $HIVE_IP:21059"

if "$HIVE_HOME/bin/schematool" -dbType derby -info > "$LOG" 2>&1; then
  echo "  схема metastore уже инициализирована"
else
  echo "  инициализация схемы metastore"
  if ! "$HIVE_HOME/bin/schematool" -dbType derby -initSchema >> "$LOG" 2>&1; then
    echo "  schematool -initSchema упал"
    tail -40 "$LOG"
    exit 1
  fi
fi

"$HIVE_HOME/bin/schematool" -dbType derby -info | tee -a "$LOG"
grep -q "Metastore schema version" "$LOG" || { echo "нет версии схемы в $LOG"; exit 1; }
cp "$LOG" "$DPE_BASE/homeworks/hw3/schema_tool.log"
echo "  схема готова"
EOF

echo "DONE"
