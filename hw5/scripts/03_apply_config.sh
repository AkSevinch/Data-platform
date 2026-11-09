#!/usr/bin/env bash
set -euo pipefail

NAME="sevinch"
LINUX_USER="dpe_sevinch"
BASE="/srv/dpe/$NAME"
DRIVER_HOST="team-02-nn"
HIVE_HOST="team-02-00"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONF_DIR="$ROOT/conf"
FLOW_DIR="$ROOT/flows"
JOB_DIR="$ROOT/jobs"

HIVE_IP=$(getent ahostsv4 "$HIVE_HOST" | awk 'NR==1{print $1}')
[ -n "$HIVE_IP" ] || { echo "не удалось определить IP для $HIVE_HOST"; exit 1; }
echo "Hive host: $HIVE_HOST ($HIVE_IP)"

echo "--> $DRIVER_HOST (копирование conf, flow и job)"
ssh -i ~/.ssh/team_internal -o ConnectTimeout=8 "team@$DRIVER_HOST" \
  "rm -rf /tmp/hw5_stage && mkdir -p /tmp/hw5_stage/conf /tmp/hw5_stage/flows /tmp/hw5_stage/jobs"
scp -q -i ~/.ssh/team_internal -o StrictHostKeyChecking=accept-new \
  "$CONF_DIR"/spark-defaults.conf "$CONF_DIR"/spark-env.sh \
  "$CONF_DIR"/hive-site.xml "$CONF_DIR"/prefect.env \
  "team@$DRIVER_HOST:/tmp/hw5_stage/conf/"
scp -q -i ~/.ssh/team_internal -o StrictHostKeyChecking=accept-new \
  "$FLOW_DIR"/sales_flow.py "team@$DRIVER_HOST:/tmp/hw5_stage/flows/"
scp -q -i ~/.ssh/team_internal -o StrictHostKeyChecking=accept-new \
  "$JOB_DIR"/spark_sales_summary.py "team@$DRIVER_HOST:/tmp/hw5_stage/jobs/"

ssh -i ~/.ssh/team_internal -o ConnectTimeout=8 "team@$DRIVER_HOST" \
  "sed -i 's/__HIVE_HOST__/$HIVE_IP/g' /tmp/hw5_stage/conf/spark-defaults.conf /tmp/hw5_stage/conf/hive-site.xml"

ssh -i ~/.ssh/team_internal -o ConnectTimeout=8 "team@$DRIVER_HOST" \
  "sudo -iu $LINUX_USER bash -s" <<EOF
set -euo pipefail
source ~/.dpe_env
mkdir -p "\$DPE_BASE/conf/hw5" "\$DPE_BASE/homeworks/hw5/flows" "\$DPE_BASE/homeworks/hw5/jobs"
cp /tmp/hw5_stage/conf/spark-defaults.conf /tmp/hw5_stage/conf/spark-env.sh \
  /tmp/hw5_stage/conf/hive-site.xml /tmp/hw5_stage/conf/prefect.env "\$DPE_BASE/conf/hw5/"
cp /tmp/hw5_stage/flows/sales_flow.py "\$DPE_BASE/homeworks/hw5/flows/"
cp /tmp/hw5_stage/jobs/spark_sales_summary.py "\$DPE_BASE/homeworks/hw5/jobs/"
chmod 644 "\$DPE_BASE/conf/hw5/"* "\$DPE_BASE/homeworks/hw5/flows/sales_flow.py" "\$DPE_BASE/homeworks/hw5/jobs/spark_sales_summary.py"
grep -q '$HIVE_IP' "\$DPE_BASE/conf/hw5/hive-site.xml"
echo "  конфиги и исходники на месте"
EOF

ssh -i ~/.ssh/team_internal -o ConnectTimeout=8 "team@$DRIVER_HOST" \
  "rm -rf /tmp/hw5_stage"

echo "--> $DRIVER_HOST (HDFS-архив Spark)"
ssh -i ~/.ssh/team_internal -o ConnectTimeout=8 "team@$DRIVER_HOST" \
  "sudo -iu $LINUX_USER bash -s" <<'EOF'
set -euo pipefail
source ~/.dpe_env
export HADOOP_CONF_DIR="$DPE_BASE/conf/hw2"
export JAVA_HOME="$DPE_BASE/dist/jdk8"

SPARK_HOME="$DPE_BASE/dist/spark"
ARCHIVE="$DPE_BASE/tmp/hw5/spark-libs.zip"

hdfs dfs -mkdir -p /user/dpe_sevinch/spark/jars /user/dpe_sevinch/spark/staging
hdfs dfs -chmod 755 /user/dpe_sevinch/spark /user/dpe_sevinch/spark/jars /user/dpe_sevinch/spark/staging

if ! hdfs dfs -test -e /user/dpe_sevinch/spark/spark-libs.zip; then
  if [ ! -s "$ARCHIVE" ]; then
    echo "  сборка $ARCHIVE"
    (cd "$SPARK_HOME/jars" && "$JAVA_HOME/bin/jar" cf "$ARCHIVE" .)
  fi
  hdfs dfs -put -f "$ARCHIVE" /user/dpe_sevinch/spark/spark-libs.zip
  hdfs dfs -chmod 644 /user/dpe_sevinch/spark/spark-libs.zip
fi

hdfs dfs -ls -h /user/dpe_sevinch/spark/spark-libs.zip
EOF

echo "DONE"
