#!/usr/bin/env bash
set -euo pipefail

NODES=("team-02-nn" "team-02-00" "team-02-01")

run() { # run <host> <script>
  ssh -i ~/.ssh/team_internal -o ConnectTimeout=8 "team@$1" \
    "sudo -iu dpe_sevinch bash -s" <<< "$2"
}

hw2_env() {
cat <<'EOF'
source ~/.dpe_env
export HADOOP_CONF_DIR=/srv/dpe/sevinch/conf/hw2
export HADOOP_LOG_DIR=/srv/dpe/sevinch/logs/hw2
export HADOOP_PID_DIR=/srv/dpe/sevinch/pids/hw2
export HADOOP_TMP_DIR=/srv/dpe/sevinch/tmp/hw2
EOF
}

echo "--> team-02-nn (jobhistory + timeline + resourcemanager)"
run "team-02-nn" "$(hw2_env)
mapred --daemon stop historyserver 2>&1 | tail -1 || true
yarn --daemon stop timelineserver 2>&1 | tail -1 || true
yarn --daemon stop resourcemanager 2>&1 | tail -1 || true"

for HOST in "${NODES[@]}"; do
  echo "--> $HOST (nodemanager)"
  run "$HOST" "$(hw2_env)
yarn --daemon stop nodemanager 2>&1 | tail -1 || true"
done

echo "остались процессы YARN dpe_sevinch? (должно быть пусто)"
for HOST in "${NODES[@]}"; do
  echo "--> $HOST"
  ssh -i ~/.ssh/team_internal -o ConnectTimeout=8 "team@$HOST" \
    "ps -eo user,cmd | grep dpe_sevinch | grep -E 'ResourceManager|NodeManager|JobHistoryServer|ApplicationHistoryServer' | grep -v grep || echo '  none'"
done

echo "архивация логов запуска в logs/hw2/prev"
for HOST in "${NODES[@]}"; do
  ssh -i ~/.ssh/team_internal -o ConnectTimeout=8 "team@$HOST" \
    "sudo -iu dpe_sevinch bash -s" <<'ARCH'
mkdir -p /srv/dpe/sevinch/logs/hw2/prev
cd /srv/dpe/sevinch/logs/hw2
for f in *.log *.out; do [ -f "$f" ] && mv "$f" prev/; done
true
ARCH
done

echo "DONE (демоны HDFS ДЗ1 продолжают работать)"
