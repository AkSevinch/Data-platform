#!/usr/bin/env bash
set -euo pipefail

NAME="sevinch"
LINUX_USER="dpe_sevinch"
BASE="/srv/dpe/$NAME"
HW="hw2"
NODES=("team-02-nn" "team-02-00" "team-02-01")
CONF_DIR="$(cd "$(dirname "$0")/../conf" && pwd)"

for HOST in "${NODES[@]}"; do
  echo "--> $HOST"
  scp -q -i ~/.ssh/team_internal -o StrictHostKeyChecking=accept-new \
    "$CONF_DIR"/core-site.xml "$CONF_DIR"/hdfs-site.xml "$CONF_DIR"/yarn-site.xml \
    "$CONF_DIR"/mapred-site.xml "$CONF_DIR"/hadoop-env.sh "$CONF_DIR"/workers \
    "team@$HOST:/tmp/"
  ssh -i ~/.ssh/team_internal -o ConnectTimeout=8 "team@$HOST" "
    sudo sed -i 's/__NODE__/$HOST/' /tmp/yarn-site.xml
    sudo cp /tmp/{core-site.xml,hdfs-site.xml,yarn-site.xml,mapred-site.xml,hadoop-env.sh,workers} $BASE/conf/$HW/
    HADOOP_HOME_DIR=$BASE/dist/hadoop
    sudo cp \$HADOOP_HOME_DIR/etc/hadoop/capacity-scheduler.xml \$HADOOP_HOME_DIR/etc/hadoop/log4j.properties $BASE/conf/$HW/
    sudo rm -f /tmp/{core-site.xml,hdfs-site.xml,yarn-site.xml,mapred-site.xml,hadoop-env.sh,workers}
    sudo chown -R $LINUX_USER:$LINUX_USER $BASE/conf/$HW
    echo 'files:'; sudo -iu $LINUX_USER ls $BASE/conf/$HW/
  "
done

echo "DONE"
