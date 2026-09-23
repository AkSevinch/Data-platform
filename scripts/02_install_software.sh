#!/usr/bin/env bash
# скачивает и распаковывает JDK 8 и Hadoop на каждой ноде в /srv/dpe/sevinch/dist
set -euo pipefail

NAME="sevinch"
LINUX_USER="dpe_sevinch"
BASE="/srv/dpe/$NAME"
NODES=("team-02-nn" "team-02-00" "team-02-01")

JDK_URL="https://github.com/adoptium/temurin8-binaries/releases/download/jdk8u412-b08/OpenJDK8U-jdk_x64_linux_hotspot_8u412b08.tar.gz"
HADOOP_URL="https://dlcdn.apache.org/hadoop/common/hadoop-3.3.6/hadoop-3.3.6.tar.gz"

INSTALL_SCRIPT=$(cat <<INSTALL_EOF
#!/usr/bin/env bash
set -euo pipefail
source ~/.dpe_env
mkdir -p "\$DPE_BASE/dist/downloads"
cd "\$DPE_BASE/dist"
curl -fL -m 1800 -o downloads/jdk8.tgz "$JDK_URL"
curl -fL -m 1800 -o downloads/hadoop-3.3.6.tar.gz "$HADOOP_URL"
[ -d jdk8 ] || { tar xzf downloads/jdk8.tgz && mv jdk8u412-b08 jdk8; }
[ -d hadoop ] || { tar xzf downloads/hadoop-3.3.6.tar.gz && mv hadoop-3.3.6 hadoop; }
echo "installed:"; ls -ld "\$DPE_BASE/dist/jdk8" "\$DPE_BASE/dist/hadoop"
INSTALL_EOF
)

for HOST in "${NODES[@]}"; do
  echo "--> $HOST"
  ssh -i ~/.ssh/team_internal -o StrictHostKeyChecking=accept-new -o ConnectTimeout=8 \
    "team@$HOST" "sudo -iu $LINUX_USER bash -s" <<< "$INSTALL_SCRIPT"
done

echo "DONE"