#!/usr/bin/env bash
# раскатывает конфиги из conf/ в /srv/dpe/sevinch/conf/hw1 на всех нодах
set -euo pipefail

NAME="sevinch"
LINUX_USER="dpe_sevinch"
BASE="/srv/dpe/$NAME"
HW="hw1"
NODES=("team-02-nn" "team-02-00" "team-02-01")
CONF_DIR="$(cd "$(dirname "$0")/../conf" && pwd)"

for HOST in "${NODES[@]}"; do
  echo "--> $HOST"
  scp -q -i ~/.ssh/team_internal -o StrictHostKeyChecking=accept-new \
    "$CONF_DIR"/core-site.xml "$CONF_DIR"/hdfs-site.xml \
    "$CONF_DIR"/workers "$CONF_DIR"/hadoop-env.sh "$CONF_DIR"/log4j.properties \
    "team@$HOST:/tmp/"
  ssh -i ~/.ssh/team_internal -o ConnectTimeout=8 "team@$HOST" "
    sudo cp /tmp/{core-site.xml,hdfs-site.xml,workers,hadoop-env.sh,log4j.properties} $BASE/conf/$HW/
    sudo chown -R $LINUX_USER:$LINUX_USER $BASE/conf/$HW
    echo 'files:'; sudo -iu $LINUX_USER ls -la $BASE/conf/$HW/
  "
done

echo "DONE"