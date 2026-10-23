#!/usr/bin/env bash
set -euo pipefail

LINUX_USER="dpe_sevinch"
HIVE_HOST="team-02-00"

HIVE_IP=$(getent ahostsv4 "$HIVE_HOST" | awk 'NR==1{print $1}')
[ -n "$HIVE_IP" ] || { echo "не удалось определить IP для $HIVE_HOST"; exit 1; }

echo "--> $HIVE_HOST"
ssh -i ~/.ssh/team_internal -o ConnectTimeout=8 \
  "team@$HIVE_HOST" "sudo -iu $LINUX_USER env HIVE_IP=$HIVE_IP bash -s" <<'EOF'
set -euo pipefail
source ~/.dpe_env
source "$DPE_BASE/conf/hw3/hive-env.sh"

OUT="$DPE_BASE/homeworks/hw3/verify.txt"
FAILED=0
: > "$OUT"

echo "1. порты Hive" | tee -a "$OUT"
for p in 21050 21051 21053 21059; do
  if ss -ltn 2>/dev/null | grep -q ":$p "; then
    echo "   $p LISTEN" | tee -a "$OUT"
  else
    echo "   $p НЕ слушает" | tee -a "$OUT"
    FAILED=1
  fi
done

echo "2. процессы Hive только от $(id -un)" | tee -a "$OUT"
ps -u "$(id -un)" -o pid=,cmd= | grep -E 'NetworkServerControl|HiveMetaStore|HiveServer2' | grep -v grep | tee -a "$OUT" || true
n=$(ps -u "$(id -un)" -o cmd= | grep -cE 'NetworkServerControl|HiveMetaStore|HiveServer2' || true)
[ "$n" -ge 3 ] || { echo "   ожидались Derby, Metastore, HiveServer2" | tee -a "$OUT"; FAILED=1; }
other=$(ps -eo user:20=,cmd= | grep -E 'HiveMetaStore|HiveServer2|NetworkServerControl' | grep -v grep | grep -vE "^ *$(id -un) " | wc -l || true)
[ "$other" -eq 0 ] || { echo "   есть процессы Hive от других пользователей: $other" | tee -a "$OUT"; FAILED=1; }

echo "3. beeline и удалённый metastore" | tee -a "$OUT"
BEELINE="$HIVE_HOME/bin/beeline -u jdbc:hive2://$HIVE_IP:21050/default -n $(id -un) --silent=true"
$BEELINE -e "SET hive.metastore.uris; SHOW DATABASES;" > /tmp/hw3_verify_beeline.out 2>&1 || {
  echo "   beeline не смог подключиться" | tee -a "$OUT"; tail -30 /tmp/hw3_verify_beeline.out | tee -a "$OUT"; FAILED=1;
}
cat /tmp/hw3_verify_beeline.out | tee -a "$OUT"
grep -q "thrift://$HIVE_IP:21053" /tmp/hw3_verify_beeline.out || {
  echo "   не видно удалённого hive.metastore.uris" | tee -a "$OUT"; FAILED=1;
}
grep -q "default" /tmp/hw3_verify_beeline.out || {
  echo "   база default не видна" | tee -a "$OUT"; FAILED=1;
}

echo "4. HiveServer2 Web UI" | tee -a "$OUT"
CODE=$(curl -s -m 5 -o /dev/null -w '%{http_code}' "http://$HIVE_IP:21051/" || echo 000)
echo "   HTTP $CODE http://$HIVE_IP:21051/" | tee -a "$OUT"
{ [ "$CODE" = "200" ] || [ "$CODE" = "302" ]; } || FAILED=1

echo "5. критические ошибки в логах" | tee -a "$OUT"
grep -hE 'FATAL|NoSuchMethodError|ClassNotFoundException|NoClassDefFoundError' \
  "$DPE_BASE/logs/hw3/metastore.out" "$DPE_BASE/logs/hw3/hiveserver2.out" \
  "$DPE_BASE/logs/hw3/hive.log" 2>/dev/null | head -20 | tee -a "$OUT" || true
crit=$(grep -hE 'FATAL|NoSuchMethodError|ClassNotFoundException|NoClassDefFoundError' \
  "$DPE_BASE/logs/hw3/metastore.out" "$DPE_BASE/logs/hw3/hiveserver2.out" \
  "$DPE_BASE/logs/hw3/hive.log" 2>/dev/null | wc -l || true)
echo "   критических строк: $crit" | tee -a "$OUT"
err=$(grep -h 'ERROR' "$DPE_BASE/logs/hw3/metastore.out" "$DPE_BASE/logs/hw3/hiveserver2.out" 2>/dev/null | wc -l || true)
echo "   ERROR (информационно): $err" | tee -a "$OUT"
[ "$crit" -eq 0 ] || FAILED=1

echo "6. metastore не embedded" | tee -a "$OUT"
grep -q "jdbc:derby://$HIVE_IP:21059/metastore_sevinch_hw3" "$DPE_BASE/conf/hw3/hive-site.xml" \
  && echo "   JDBC URL сетевой" | tee -a "$OUT" || { echo "   JDBC URL не сетевой" | tee -a "$OUT"; FAILED=1; }
ps -u "$(id -un)" -o cmd= | grep -q 'org.apache.derby.drda.NetworkServerControl start' \
  && echo "   Derby NetworkServerControl запущен" | tee -a "$OUT" || { echo "   Derby network server не найден" | tee -a "$OUT"; FAILED=1; }

echo | tee -a "$OUT"
if [ "$FAILED" = 0 ]; then
  echo "VERIFY: OK" | tee -a "$OUT"
else
  echo "VERIFY: FAIL" | tee -a "$OUT"
  exit 1
fi
EOF

echo "DONE"
