#!/usr/bin/env bash
set -euo pipefail

NN="team-02-nn"
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

echo "--> HDFS-каталоги для YARN и JobHistory"
run "$NN" "$(hw2_env)
hdfs dfs -mkdir -p /yarn/app-logs /user/dpe_sevinch/mapred/done_intermediate /user/dpe_sevinch/mapred/done
hdfs dfs -chmod -R 777 /yarn/app-logs"

echo "--> $NN (resourcemanager)"
run "$NN" "$(hw2_env)
yarn --daemon start resourcemanager || true"

for HOST in "${NODES[@]}"; do
  echo "--> $HOST (nodemanager)"
  run "$HOST" "$(hw2_env)
yarn --daemon start nodemanager || true"
done

echo "ждём готовности ResourceManager и регистрации 3 нод"
run "$NN" "$(hw2_env)
ok=0
for i in \$(seq 1 45); do
  n=\$(yarn node -list 2>/dev/null | grep -c RUNNING || true)
  if [ \"\$n\" -ge 3 ]; then ok=1; break; fi
  sleep 2
done
yarn node -list 2>/dev/null | grep -E 'Node-Id|RUNNING' || true
[ \"\$ok\" = 1 ] || { echo 'ноды не зарегистрировались'; exit 1; }"

echo "--> $NN (jobhistoryserver + timelineserver)"
run "$NN" "$(hw2_env)
mapred --daemon start historyserver || true
yarn --daemon start timelineserver || true"

echo "ждём поднятия портов jobhistory и timeline"
run "$NN" 'ok=0
for i in $(seq 1 30); do
  c=$(ss -ltn | grep -cE ":21120 |:21888 |:21188 ")
  if [ "$c" -ge 3 ]; then ok=1; break; fi
  sleep 1
done
ss -ltn | grep -E ":21120 |:21888 |:21188 "
[ "$ok" = 1 ] || { echo "порты не поднялись"; exit 1; }'

echo "DONE. Проверка: bash hw2/scripts/04_verify.sh"
