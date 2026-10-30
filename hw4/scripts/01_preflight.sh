#!/usr/bin/env bash
set -euo pipefail

NAME="sevinch"
LINUX_USER="dpe_sevinch"
BASE="/srv/dpe/$NAME"
HW="hw4"
NODES=("team-02-nn" "team-02-00" "team-02-01")
DRIVER_HOST="team-02-nn"
HIVE_HOST="team-02-00"
SPARK_UI_PORT="21404"
SPARK_URL="https://archive.apache.org/dist/spark/spark-3.5.1/spark-3.5.1-bin-hadoop3.tgz"

for HOST in "${NODES[@]}"; do
  echo "--> $HOST (каталоги HW4)"
  ssh -i ~/.ssh/team_internal -o ConnectTimeout=8 "team@$HOST" "
    set -e
    sudo mkdir -p '$BASE/conf/$HW' '$BASE/logs/$HW' '$BASE/pids/$HW' \
      '$BASE/tmp/$HW/scratch' '$BASE/tmp/$HW/spark' '$BASE/homeworks/$HW/jobs'
    sudo chown -R $LINUX_USER:$LINUX_USER '$BASE/conf/$HW' '$BASE/logs/$HW' \
      '$BASE/pids/$HW' '$BASE/tmp/$HW' '$BASE/homeworks/$HW'
    echo '  каталоги готовы'
  "
done

echo "--> $DRIVER_HOST (порт Spark UI $SPARK_UI_PORT)"
ssh -i ~/.ssh/team_internal -o ConnectTimeout=8 "team@$DRIVER_HOST" "
  set -e
  [ -x '$BASE/dist/jdk8/bin/java' ] || { echo '  нет JDK8'; exit 1; }
  [ -x '$BASE/dist/hadoop/bin/hdfs' ] || { echo '  нет Hadoop'; exit 1; }
  if ss -ltn 2>/dev/null | grep -q ':$SPARK_UI_PORT '; then
    echo '  порт $SPARK_UI_PORT уже занят'; exit 1
  fi
  avail=\$(free -m | awk '/Mem:/{print \$7}')
  disk=\$(df -Pm '$BASE' | awk 'NR==2{print \$4}')
  echo \"  available memory: \${avail} MB\"
  echo \"  free disk: \${disk} MB\"
  [ \"\$avail\" -ge 1200 ] || { echo '  мало свободной памяти'; exit 1; }
  [ \"\$disk\" -ge 2000 ] || { echo '  мало свободного диска'; exit 1; }
  echo '  порт $SPARK_UI_PORT свободен'
"

echo "--> $DRIVER_HOST (доступность Spark 3.5.1)"
ssh -i ~/.ssh/team_internal -o ConnectTimeout=8 "team@$DRIVER_HOST" \
  "set -e; code=\$(curl -sIL -m 25 -o /dev/null -w '%{http_code}' '$SPARK_URL' || true); echo \"  HTTP \$code\"; [ \"\$code\" = 200 ] || { echo '  Spark archive недоступен'; exit 1; }"

echo "--> HDFS и исходный CSV"
ssh -i ~/.ssh/team_internal -o ConnectTimeout=8 "team@$DRIVER_HOST" \
  "sudo -iu $LINUX_USER bash -s" <<'EOF'
set -euo pipefail
source ~/.dpe_env
export HADOOP_CONF_DIR="$DPE_BASE/conf/hw2"
LIVE=$(hdfs dfsadmin -report 2>/dev/null | grep -oE 'Live datanodes \([0-9]+\)' | grep -oE '[0-9]+' | head -1 || true)
echo "  live datanodes: ${LIVE:-unknown}"
[ "${LIVE:-0}" -ge 3 ] || { echo "  HDFS не здоров"; exit 1; }
hdfs dfs -test -e /user/dpe_sevinch/hw3/staging/sales.csv || {
  echo "  нет /user/dpe_sevinch/hw3/staging/sales.csv"; exit 1;
}
ROWS=$(hdfs dfs -cat /user/dpe_sevinch/hw3/staging/sales.csv | wc -l)
echo "  sales.csv rows: $ROWS"
[ "$ROWS" -eq 36 ] || { echo "  ожидалось 36 строк"; exit 1; }
EOF

echo "--> YARN (ожидаем 3 RUNNING)"
ssh -i ~/.ssh/team_internal -o ConnectTimeout=8 "team@$DRIVER_HOST" \
  "sudo -iu $LINUX_USER bash -s" <<'EOF'
set -euo pipefail
source ~/.dpe_env
export HADOOP_CONF_DIR="$DPE_BASE/conf/hw2"
n=$(yarn node -list 2>/dev/null | grep -c RUNNING || true)
yarn node -list 2>/dev/null | grep -E 'Node-Id|RUNNING' || true
echo "  RUNNING nodes: $n"
[ "$n" -ge 3 ]
EOF

echo "--> $HIVE_HOST (порты Hive)"
ssh -i ~/.ssh/team_internal -o ConnectTimeout=8 "team@$HIVE_HOST" "
  busy=''
  for p in 21050 21051 21053 21059; do
    ss -ltn 2>/dev/null | grep -q \":\$p \" || busy=\"\$busy \$p\"
  done
  if [ -n \"\$busy\" ]; then echo \"  НЕ слушают:\$busy\"; exit 1; fi
  echo '  Hive-порты 21050/21051/21053/21059 слушают'
"

if ! ssh -i ~/.ssh/team_internal -o ConnectTimeout=8 "team@$DRIVER_HOST" \
  "sudo -iu $LINUX_USER cat '$BASE/PORTS.md' 2>/dev/null" | grep -q "HW4"; then
  echo "--> запись портов HW4 в PORTS.md"
  ssh -i ~/.ssh/team_internal -o ConnectTimeout=8 "team@$DRIVER_HOST" \
    "sudo -iu $LINUX_USER bash -s" <<'EOF'
source ~/.dpe_env
cat >> "$DPE_BASE/PORTS.md" <<PORTS

## HW4 Spark on YARN (sevinch range 21000-21999)
- spark_ui: 21404
PORTS
EOF
fi

echo "DONE"
