#!/usr/bin/env bash
set -euo pipefail

NAME="sevinch"
LINUX_USER="dpe_sevinch"
BASE="/srv/dpe/$NAME"
HW="hw5"
DRIVER_HOST="team-02-nn"
SPARK_UI_PORT="21405"

echo "Participant: $NAME"
echo "Linux user: $LINUX_USER"
echo "Base directory: $BASE"
echo "Port range: 21000-21999"
echo "Homework directory: $BASE/homeworks/$HW"

echo "--> $DRIVER_HOST (каталоги HW5)"
ssh -i ~/.ssh/team_internal -o ConnectTimeout=8 "team@$DRIVER_HOST" \
  "sudo -iu $LINUX_USER bash -s" <<'EOF'
set -euo pipefail
source ~/.dpe_env
mkdir -p \
  "$DPE_BASE/conf/hw5" \
  "$DPE_BASE/logs/hw5" \
  "$DPE_BASE/pids/hw5" \
  "$DPE_BASE/tmp/hw5/scratch" \
  "$DPE_BASE/data/hw5/prefect" \
  "$DPE_BASE/homeworks/hw5/flows" \
  "$DPE_BASE/homeworks/hw5/jobs"
echo "  каталоги готовы"
EOF

echo "--> $DRIVER_HOST (Python, venv, сеть)"
ssh -i ~/.ssh/team_internal -o ConnectTimeout=8 "team@$DRIVER_HOST" \
  "sudo -iu $LINUX_USER bash -s" <<'EOF'
set -euo pipefail
source ~/.dpe_env
python3 --version
python3 -m venv --help >/dev/null
command -v curl >/dev/null
echo "  venv и curl доступны"
code=$(curl -sIL -m 30 -o /dev/null -w '%{http_code}' https://bootstrap.pypa.io/get-pip.py || true)
echo "  get-pip.py HTTP $code"
[ "$code" = 200 ] || { echo "  get-pip.py недоступен"; exit 1; }
EOF

echo "--> $DRIVER_HOST (ресурсы и порт Spark UI $SPARK_UI_PORT)"
ssh -i ~/.ssh/team_internal -o ConnectTimeout=8 "team@$DRIVER_HOST" \
  "sudo -iu $LINUX_USER bash -s" <<'EOF'
set -euo pipefail
source ~/.dpe_env
if ss -ltn 2>/dev/null | grep -q ':21405 '; then
  echo "  порт 21405 уже занят"; exit 1
fi
avail=$(free -m | awk '/Mem:/{print $7}')
disk=$(df -Pm "$DPE_BASE" | awk 'NR==2{print $4}')
echo "  available memory: ${avail} MB"
echo "  free disk: ${disk} MB"
[ "$avail" -ge 900 ] || { echo "  мало свободной памяти"; exit 1; }
[ "$disk" -ge 2000 ] || { echo "  мало свободного диска"; exit 1; }
echo "  порт 21405 свободен"
EOF

echo "--> $DRIVER_HOST (Spark 3.5.1)"
ssh -i ~/.ssh/team_internal -o ConnectTimeout=8 "team@$DRIVER_HOST" \
  "sudo -iu $LINUX_USER bash -s" <<'EOF'
set -euo pipefail
source ~/.dpe_env
[ -x "$DPE_BASE/dist/spark/bin/spark-submit" ] || {
  echo "  нет Spark 3.5.1"; exit 1;
}
"$DPE_BASE/dist/spark/bin/spark-submit" --version 2>&1 | grep -q 'version 3.5.1'
echo "  Spark 3.5.1 доступен"
EOF

echo "--> HDFS, CSV и YARN"
ssh -i ~/.ssh/team_internal -o ConnectTimeout=8 "team@$DRIVER_HOST" \
  "sudo -iu $LINUX_USER bash -s" <<'EOF'
set -euo pipefail
source ~/.dpe_env
export HADOOP_CONF_DIR="$DPE_BASE/conf/hw2"
LIVE=$(hdfs dfsadmin -report 2>/dev/null | grep -oE 'Live datanodes \([0-9]+\)' | grep -oE '[0-9]+' | head -1 || true)
echo "  live datanodes: ${LIVE:-unknown}"
[ "${LIVE:-0}" -ge 3 ] || { echo "  HDFS не здоров"; exit 1; }
hdfs dfs -test -e /user/dpe_sevinch/spark/spark-libs.zip || {
  echo "  нет spark-libs.zip, сначала выполните hw4/scripts/03_apply_config.sh"; exit 1;
}
hdfs dfs -test -e /user/dpe_sevinch/hw3/staging/sales.csv || {
  echo "  нет sales.csv"; exit 1;
}
ROWS=$(hdfs dfs -cat /user/dpe_sevinch/hw3/staging/sales.csv | wc -l)
echo "  sales.csv rows: $ROWS"
[ "$ROWS" -eq 36 ] || { echo "  ожидалось 36 строк"; exit 1; }
n=$(yarn node -list 2>/dev/null | grep -c RUNNING || true)
echo "  RUNNING NodeManagers: $n"
[ "$n" -ge 3 ] || { echo "  ожидалось 3 RUNNING NodeManager"; exit 1; }
EOF

echo "--> team-02-00 (порты Hive)"
ssh -i ~/.ssh/team_internal -o ConnectTimeout=8 "team@team-02-00" <<'EOF'
set -euo pipefail
busy=''
for port in 21050 21051 21053 21059; do
  ss -ltn 2>/dev/null | grep -q ":$port " || busy="$busy $port"
done
if [ -n "$busy" ]; then
  echo "  НЕ слушают:$busy"; exit 1
fi
echo "  Hive-порты 21050/21051/21053/21059 слушают"
EOF

if ! ssh -i ~/.ssh/team_internal -o ConnectTimeout=8 "team@$DRIVER_HOST" \
  "sudo -iu $LINUX_USER cat '$BASE/PORTS.md' 2>/dev/null" | grep -q 'HW5'; then
  echo "--> запись портов HW5 в PORTS.md"
  ssh -i ~/.ssh/team_internal -o ConnectTimeout=8 "team@$DRIVER_HOST" \
    "sudo -iu $LINUX_USER bash -s" <<'EOF'
set -euo pipefail
source ~/.dpe_env
cat >> "$DPE_BASE/PORTS.md" <<'PORTS'

## HW5 Prefect orchestration (sevinch range 21000-21999)
- spark_ui: 21405
PORTS
EOF
fi

echo "DONE"
