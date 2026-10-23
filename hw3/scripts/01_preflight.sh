#!/usr/bin/env bash
set -euo pipefail

NAME="sevinch"
LINUX_USER="dpe_sevinch"
BASE="/srv/dpe/$NAME"
HW="hw3"
NODES=("team-02-nn" "team-02-00" "team-02-01")
HIVE_HOST="team-02-00"
HIVE_PORTS=(21050 21051 21053 21059)

for HOST in "${NODES[@]}"; do
  echo "--> $HOST"
  ssh -i ~/.ssh/team_internal -o ConnectTimeout=8 "team@$HOST" "
    sudo mkdir -p '$BASE/conf/$HW' '$BASE/logs/$HW/querylog' '$BASE/pids/$HW' \
      '$BASE/tmp/$HW/scratch' '$BASE/tmp/$HW/resources' '$BASE/data/$HW/derby' \
      '$BASE/homeworks/$HW'
    sudo chown -R $LINUX_USER:$LINUX_USER '$BASE/conf/$HW' '$BASE/logs/$HW' \
      '$BASE/pids/$HW' '$BASE/tmp/$HW' '$BASE/data/$HW' '$BASE/homeworks/$HW'
    busy=''
    for p in ${HIVE_PORTS[*]}; do
      ss -ltn 2>/dev/null | grep -q \":\$p \" && busy=\"\$busy \$p\"
    done
    if [ -n \"\$busy\" ]; then echo \"  ЗАНЯТЫ порты:\$busy\"; exit 1; fi
    [ -x '$BASE/dist/jdk8/bin/java' ] || { echo '  нет JDK8'; exit 1; }
    [ -x '$BASE/dist/hadoop/bin/hdfs' ] || { echo '  нет Hadoop'; exit 1; }
    echo '  порты 21050,21051,21053,21059 свободны, каталоги готовы'
  "
done

echo "--> память на $HIVE_HOST"
ssh -i ~/.ssh/team_internal -o ConnectTimeout=8 "team@$HIVE_HOST" "
  avail=\$(free -m | awk '/Mem:/{print \$7}')
  echo \"  available: \${avail} MB\"
  [ \"\$avail\" -ge 1500 ] || { echo '  мало свободной памяти'; exit 1; }
"

echo "--> HDFS жив?"
ssh -i ~/.ssh/team_internal -o ConnectTimeout=8 team@team-02-nn \
  "sudo -iu $LINUX_USER bash -s" <<'EOF' || { echo "  HDFS не отвечает"; exit 1; }
source ~/.dpe_env
hdfs dfsadmin -report 2>/dev/null | grep -E "Live datanodes"
EOF

echo "--> YARN жив?"
ssh -i ~/.ssh/team_internal -o ConnectTimeout=8 team@team-02-nn \
  "sudo -iu $LINUX_USER bash -s" <<'EOF' || { echo "  YARN не отвечает или не все ноды RUNNING"; exit 1; }
source ~/.dpe_env
export HADOOP_CONF_DIR=$DPE_BASE/conf/hw2
n=$(yarn node -list 2>/dev/null | grep -c RUNNING || true)
yarn node -list 2>/dev/null | grep -E 'Node-Id|RUNNING' || true
[ "$n" -ge 3 ]
EOF

if ! ssh -i ~/.ssh/team_internal -o ConnectTimeout=8 team@team-02-nn \
  "sudo -iu $LINUX_USER cat '$BASE/PORTS.md' 2>/dev/null" | grep -q "HW3"; then
  echo "--> запись портов HW3 в PORTS.md"
  ssh -i ~/.ssh/team_internal -o ConnectTimeout=8 team@team-02-nn \
    "sudo -iu $LINUX_USER bash -s" <<'EOF'
source ~/.dpe_env
cat >> "$DPE_BASE/PORTS.md" <<PORTS

## HW3 Hive (sevinch range 21000-21999)
- hiveserver2_thrift: 21050
- hiveserver2_webui: 21051
- metastore_thrift: 21053
- derby_network: 21059
PORTS
EOF
fi

echo "DONE"
