#!/usr/bin/env bash
set -euo pipefail

NAME="sevinch"
LINUX_USER="dpe_sevinch"
BASE="/srv/dpe/$NAME"
NODES=("team-02-nn" "team-02-00" "team-02-01")

HIVE_URL="https://archive.apache.org/dist/hive/hive-4.0.0-alpha-2/apache-hive-4.0.0-alpha-2-bin.tar.gz"
DERBY_URL="https://archive.apache.org/dist/db/derby/db-derby-10.14.2.0/db-derby-10.14.2.0-bin.tar.gz"

INSTALL_SCRIPT=$(cat <<INSTALL_EOF
#!/usr/bin/env bash
set -euo pipefail
source ~/.dpe_env
mkdir -p "\$DPE_BASE/dist/downloads"
cd "\$DPE_BASE/dist"

[ -s downloads/hive.tar.gz ] || {
  curl -fL -m 3600 -o downloads/hive.tar.gz.part "$HIVE_URL"
  mv downloads/hive.tar.gz.part downloads/hive.tar.gz
}
[ -s downloads/derby.tar.gz ] || {
  curl -fL -m 1800 -o downloads/derby.tar.gz.part "$DERBY_URL"
  mv downloads/derby.tar.gz.part downloads/derby.tar.gz
}

[ -d hive ] || { tar xzf downloads/hive.tar.gz && mv apache-hive-4.0.0-alpha-2-bin hive; }
[ -d derby ] || { tar xzf downloads/derby.tar.gz && mv db-derby-10.14.2.0-bin derby; }

HIVE_HOME="\$DPE_BASE/dist/hive"
HADOOP_HOME="\$DPE_BASE/dist/hadoop"
DERBY_HOME="\$DPE_BASE/dist/derby"

if [ ! -f "\$HIVE_HOME/lib/derbyclient.jar" ]; then
  cp "\$DERBY_HOME/lib/derbyclient.jar" "\$HIVE_HOME/lib/"
fi

HADOOP_GUAVA=\$(ls "\$HADOOP_HOME"/share/hadoop/common/lib/guava-27*.jar 2>/dev/null | head -1 || true)
HIVE_GUAVA=\$(ls "\$HIVE_HOME"/lib/guava-*.jar 2>/dev/null | head -1 || true)
if [ -n "\$HADOOP_GUAVA" ]; then
  if [ -z "\$HIVE_GUAVA" ]; then
    cp "\$HADOOP_GUAVA" "\$HIVE_HOME/lib/"
  elif ! echo "\$HIVE_GUAVA" | grep -q 'guava-27'; then
    mkdir -p "\$HIVE_HOME/lib/disabled"
    mv "\$HIVE_GUAVA" "\$HIVE_HOME/lib/disabled/"
    cp "\$HADOOP_GUAVA" "\$HIVE_HOME/lib/"
  fi
fi

echo "  hive: \$(\$HIVE_HOME/bin/hive --version 2>/dev/null | head -1)"
echo "  guava: \$(ls "\$HIVE_HOME"/lib/guava-*.jar 2>/dev/null | xargs -n1 basename | tr '\n' ' ')"
echo "  derby client: \$(ls "\$HIVE_HOME/lib/derbyclient.jar" 2>/dev/null || echo missing)"
INSTALL_EOF
)

for HOST in "${NODES[@]}"; do
  echo "--> $HOST"
  ssh -i ~/.ssh/team_internal -o StrictHostKeyChecking=accept-new -o ConnectTimeout=8 \
    "team@$HOST" "sudo -iu $LINUX_USER bash -s" <<< "$INSTALL_SCRIPT"
done

echo "DONE"
