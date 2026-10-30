#!/usr/bin/env bash
set -euo pipefail

NAME="sevinch"
LINUX_USER="dpe_sevinch"
BASE="/srv/dpe/$NAME"
DRIVER_HOST="team-02-nn"
HIVE_HOST="team-02-00"
CONF_DIR="$(cd "$(dirname "$0")/../conf" && pwd)"

HIVE_IP=$(getent ahostsv4 "$HIVE_HOST" | awk 'NR==1{print $1}')
[ -n "$HIVE_IP" ] || { echo "не удалось определить IP для $HIVE_HOST"; exit 1; }
echo "Hive host: $HIVE_HOST ($HIVE_IP)"

echo "--> $DRIVER_HOST (конфиги spark)"
ssh -i ~/.ssh/team_internal -o ConnectTimeout=8 "team@$DRIVER_HOST" \
  "rm -rf /tmp/hw4_conf && mkdir -p /tmp/hw4_conf"
scp -q -i ~/.ssh/team_internal -o StrictHostKeyChecking=accept-new \
  "$CONF_DIR"/spark-defaults.conf "$CONF_DIR"/spark-env.sh "$CONF_DIR"/hive-site.xml \
  "team@$DRIVER_HOST:/tmp/hw4_conf/"
ssh -i ~/.ssh/team_internal -o ConnectTimeout=8 "team@$DRIVER_HOST" "
  set -e
  sudo sed -i 's/__HIVE_HOST__/$HIVE_IP/g' /tmp/hw4_conf/spark-defaults.conf /tmp/hw4_conf/hive-site.xml
  sudo mkdir -p '$BASE/conf/hw4' '$BASE/logs/hw4' '$BASE/pids/hw4' '$BASE/tmp/hw4/scratch'
  sudo cp /tmp/hw4_conf/{spark-defaults.conf,spark-env.sh,hive-site.xml} '$BASE/conf/hw4/'
  sudo chown -R $LINUX_USER:$LINUX_USER '$BASE/conf/hw4' '$BASE/logs/hw4' '$BASE/pids/hw4' '$BASE/tmp/hw4'
  sudo rm -rf /tmp/hw4_conf
  sudo -iu $LINUX_USER grep -q '$HIVE_IP' '$BASE/conf/hw4/hive-site.xml'
  echo '  конфиги на месте'
"

echo "--> $DRIVER_HOST (HDFS-каталоги и архив jar)"
ssh -i ~/.ssh/team_internal -o ConnectTimeout=8 "team@$DRIVER_HOST" \
  "sudo -iu $LINUX_USER bash -s" <<'EOF'
set -euo pipefail
source ~/.dpe_env
export HADOOP_CONF_DIR="$DPE_BASE/conf/hw2"

SPARK_HOME="$DPE_BASE/dist/spark"
ARCHIVE="$DPE_BASE/tmp/hw4/spark-libs.zip"

hdfs dfs -mkdir -p /user/dpe_sevinch/spark/jars /user/dpe_sevinch/spark/staging
hdfs dfs -chmod 755 /user/dpe_sevinch/spark /user/dpe_sevinch/spark/jars /user/dpe_sevinch/spark/staging

if [ ! -s "$ARCHIVE" ]; then
  echo "  сборка $ARCHIVE (может занять ~1 минуту)"
  (cd "$SPARK_HOME/jars" && jar cf "$ARCHIVE" .)
fi
[ -s "$ARCHIVE" ] || { echo "  архив Spark не собрался"; exit 1; }
jar tf "$ARCHIVE" | sed -n '1,5p' || { echo "  архив повреждён"; exit 1; }

hdfs dfs -put -f "$ARCHIVE" /user/dpe_sevinch/spark/spark-libs.zip
hdfs dfs -chmod 644 /user/dpe_sevinch/spark/spark-libs.zip
echo "  HDFS:"
hdfs dfs -ls -h /user/dpe_sevinch/spark
hdfs dfs -ls -h /user/dpe_sevinch/spark/spark-libs.zip
EOF

echo "DONE"
