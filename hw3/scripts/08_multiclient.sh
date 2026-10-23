#!/usr/bin/env bash
set -euo pipefail

LINUX_USER="dpe_sevinch"
HIVE_HOST="team-02-00"
CLIENT2="${CLIENT2:-team-02-nn}"

HIVE_IP=$(getent ahostsv4 "$HIVE_HOST" | awk 'NR==1{print $1}')
[ -n "$HIVE_IP" ] || { echo "не удалось определить IP для $HIVE_HOST"; exit 1; }

LONG_Q="SELECT reflect('java.lang.Thread','sleep',25000L) AS slept;"

printf '%s\n' "$LONG_Q" > /tmp/hw3_long.sql
scp -q -i ~/.ssh/team_internal /tmp/hw3_long.sql "team@$HIVE_HOST:/tmp/hw3_long.sql"

echo "--> клиент A на $HIVE_HOST (долгий запрос)"
ssh -i ~/.ssh/team_internal -o ConnectTimeout=8 \
  "team@$HIVE_HOST" "sudo -iu $LINUX_USER env HIVE_IP=$HIVE_IP bash -s" <<'EOF' > /tmp/hw3_client_a.log 2>&1 &
set -euo pipefail
source ~/.dpe_env
source "$DPE_BASE/conf/hw3/hive-env.sh"
"$HIVE_HOME/bin/beeline" -u "jdbc:hive2://$HIVE_IP:21050/default" -n "$(id -un)" \
  --silent=true -f /tmp/hw3_long.sql
EOF
PID_A=$!
sleep 5

if ! kill -0 "$PID_A" 2>/dev/null; then
  echo "клиент A завершился слишком быстро"
  cat /tmp/hw3_client_a.log
  exit 1
fi

echo "--> клиент B на $CLIENT2 (короткие запросы, пока A работает)"
B_OUT=/tmp/hw3_client_b.log
ssh -i ~/.ssh/team_internal -o ConnectTimeout=8 \
  "team@$CLIENT2" "sudo -iu $LINUX_USER env HIVE_IP=$HIVE_IP bash -s" > "$B_OUT" 2>&1 <<'EOF'
set -euo pipefail
source ~/.dpe_env
source "$DPE_BASE/conf/hw3/hive-env.sh"
"$HIVE_HOME/bin/beeline" -u "jdbc:hive2://$HIVE_IP:21050/default" -n "$(id -un)" \
  --silent=true -e "SELECT current_user(), current_database(); SHOW PARTITIONS hw3.sales_part;"
EOF

if kill -0 "$PID_A" 2>/dev/null; then
  OVERLAP=1
else
  OVERLAP=0
fi

wait "$PID_A" || { echo "клиент A упал"; cat /tmp/hw3_client_a.log; exit 1; }

grep -q "dt=" "$B_OUT" || { echo "клиент B не увидел партиции"; cat "$B_OUT"; exit 1; }

{
  echo "client A: $HIVE_HOST (pid $PID_A)"
  echo "client B: $CLIENT2"
  echo "A query: $LONG_Q"
  echo "B output:"
  cat "$B_OUT"
  echo
  if [ "$OVERLAP" = 1 ]; then
    echo "OVERLAP: YES (B завершился, пока A ещё работал)"
    echo "MULTICLIENT: OK"
  else
    echo "OVERLAP: NO"
    echo "MULTICLIENT: FAIL"
  fi
} | tee /tmp/hw3_multiclient_result.txt

[ "$OVERLAP" = 1 ] || exit 1
echo "DONE"
