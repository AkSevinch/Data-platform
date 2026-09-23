#!/usr/bin/env bash
# 01_create_user.sh
# Создаёт на каждой ноде кластера пользователя dpe_sevinch, каталоги и конфиг окружения.
# Выполнять с edge-ноды (team-02-en) от пользователя team.
set -euo pipefail

NAME="sevinch"
LINUX_USER="dpe_sevinch"
LINUX_USER_HOME="/home/$LINUX_USER"
BASE="/srv/dpe/$NAME"
HW="hw1"
NODES=("team-02-nn" "team-02-00" "team-02-01")

SETUP_SCRIPT=$(cat <<'SETUP_EOF'
#!/usr/bin/env bash
set -euo pipefail
NAME="__NAME__"
LINUX_USER="__LINUX_USER__"
LINUX_USER_HOME="/home/$LINUX_USER"
BASE="/srv/dpe/$NAME"
HW="__HW__"

sudo useradd -m -s /bin/bash "$LINUX_USER" 2>/dev/null || true
sudo mkdir -p "$BASE"/{conf,logs,pids,tmp,data,homeworks,bin,dist} \
  "$BASE/conf/$HW" "$BASE/logs/$HW" "$BASE/pids/$HW" \
  "$BASE/tmp/$HW" "$BASE/data/$HW" "$BASE/homeworks/$HW"
sudo chown -R "$LINUX_USER":"$LINUX_USER" "$BASE"
sudo chmod 755 "$BASE"

sudo -u "$LINUX_USER" tee "$LINUX_USER_HOME/.dpe_env" >/dev/null <<EOF
export DPE_NAME="$NAME"
export DPE_BASE="$BASE"
export DPE_HW="\${DPE_HW:-$HW}"
export DPE_CONF_DIR="\$DPE_BASE/conf"
export DPE_LOG_DIR="\$DPE_BASE/logs"
export DPE_PID_DIR="\$DPE_BASE/pids"
export DPE_TMP_DIR="\$DPE_BASE/tmp"
export DPE_DATA_DIR="\$DPE_BASE/data"
export DPE_HOMEWORK_DIR="\$DPE_BASE/homeworks"
export JAVA_HOME="\$DPE_BASE/dist/jdk8"
export HADOOP_HOME="\$DPE_BASE/dist/hadoop"
export HADOOP_CONF_DIR="\$DPE_CONF_DIR/\$DPE_HW"
export HADOOP_LOG_DIR="\$DPE_LOG_DIR/\$DPE_HW"
export HADOOP_PID_DIR="\$DPE_PID_DIR/\$DPE_HW"
export HADOOP_TMP_DIR="\$DPE_TMP_DIR/\$DPE_HW"
export PATH="\$JAVA_HOME/bin:\$HADOOP_HOME/bin:\$HADOOP_HOME/sbin:\$PATH"
EOF

for RC in .bashrc .profile; do
  sudo -u "$LINUX_USER" bash -c "grep -q 'source ~/.dpe_env' '$LINUX_USER_HOME/$RC' || echo 'source ~/.dpe_env' >> '$LINUX_USER_HOME/$RC'"
done

if ! sudo -u "$LINUX_USER" grep -q "HW1 HDFS cluster" "$BASE/PORTS.md" 2>/dev/null; then
  sudo -u "$LINUX_USER" tee -a "$BASE/PORTS.md" >/dev/null <<EOF

## HW1 HDFS cluster (sevinch range 21000-21999)
- namenode_rpc: 21020
- namenode_http: 21970
- secondarynn_rpc: 21069
- secondarynn_http: 21968
- datanode_ipc: 21064
- datanode_transfer: 21066
- datanode_http: 21964
EOF
fi

echo "OK on $(hostname)"
SETUP_EOF
)

SETUP_SCRIPT=${SETUP_SCRIPT//__NAME__/$NAME}
SETUP_SCRIPT=${SETUP_SCRIPT//__LINUX_USER__/$LINUX_USER}
SETUP_SCRIPT=${SETUP_SCRIPT//__HW__/$HW}

for HOST in "${NODES[@]}"; do
  echo "===== $HOST ====="
  ssh -i ~/.ssh/team_internal -o StrictHostKeyChecking=accept-new -o ConnectTimeout=8 \
    "team@$HOST" "bash -s" <<< "$SETUP_SCRIPT"
done

echo "DONE"