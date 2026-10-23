#!/usr/bin/env bash
set -euo pipefail

NAME="sevinch"
LINUX_USER="dpe_sevinch"
BASE="/srv/dpe/$NAME"
HW="hw3"
NODES=("team-02-nn" "team-02-00" "team-02-01")
HIVE_HOST="team-02-00"
CONF_DIR="$(cd "$(dirname "$0")/../conf" && pwd)"

HIVE_IP=$(getent ahostsv4 "$HIVE_HOST" | awk 'NR==1{print $1}')
[ -n "$HIVE_IP" ] || { echo "не удалось определить IP для $HIVE_HOST"; exit 1; }
echo "Hive host: $HIVE_HOST ($HIVE_IP)"

for HOST in "${NODES[@]}"; do
  echo "--> $HOST"
  scp -q -i ~/.ssh/team_internal -o StrictHostKeyChecking=accept-new \
    "$CONF_DIR"/hive-site.xml "$CONF_DIR"/hive-env.sh "$CONF_DIR"/hive-log4j2.properties \
    "team@$HOST:/tmp/"
  ssh -i ~/.ssh/team_internal -o ConnectTimeout=8 "team@$HOST" "
    set -e
    sudo mkdir -p '$BASE/conf/$HW' '$BASE/logs/$HW' '$BASE/pids/$HW' \
      '$BASE/tmp/$HW' '$BASE/homeworks/$HW'
    sudo sed -i 's/__HIVE_HOST__/$HIVE_IP/g' /tmp/hive-site.xml
    sudo cp /tmp/{hive-site.xml,hive-env.sh,hive-log4j2.properties} $BASE/conf/$HW/
    sudo rm -f /tmp/{hive-site.xml,hive-env.sh,hive-log4j2.properties}
    sudo chown -R $LINUX_USER:$LINUX_USER $BASE/conf/$HW $BASE/logs/$HW \
      $BASE/pids/$HW $BASE/tmp/$HW $BASE/homeworks/$HW
    sudo -iu $LINUX_USER grep -q '$HIVE_IP' $BASE/conf/$HW/hive-site.xml
    echo '  конфиги на месте'
  "
done

echo "--> HDFS-каталоги Hive"
ssh -i ~/.ssh/team_internal -o ConnectTimeout=8 team@team-02-nn \
  "sudo -iu $LINUX_USER bash -s" <<'EOF'
source ~/.dpe_env
export HADOOP_CONF_DIR=$DPE_BASE/conf/hw2
hdfs dfs -mkdir -p /user/dpe_sevinch/hive/warehouse /user/dpe_sevinch/hive/scratch \
  /user/dpe_sevinch/hw3/staging
hdfs dfs -chmod 755 /user/dpe_sevinch/hive /user/dpe_sevinch/hive/warehouse \
  /user/dpe_sevinch/hw3 /user/dpe_sevinch/hw3/staging
hdfs dfs -chmod 777 /user/dpe_sevinch/hive/scratch
hdfs dfs -ls -d /user/dpe_sevinch/hive/warehouse /user/dpe_sevinch/hive/scratch \
  /user/dpe_sevinch/hw3/staging
EOF

echo "DONE"
