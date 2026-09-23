#!/usr/bin/env bash
# останавливает только демоны dpe_sevinch, чужие процессы не трогает
set -euo pipefail

run() { # run <host> <script>
  ssh -i ~/.ssh/team_internal -o ConnectTimeout=8 "team@$1" \
    "sudo -iu dpe_sevinch bash -s" <<< "$2"
}

stop_dn() {
cat <<'EOF'
source ~/.dpe_env
hdfs --daemon stop datanode 2>&1 | tail -1
EOF
}

stop_nn() {
cat <<'EOF'
source ~/.dpe_env
hdfs --daemon stop datanode 2>&1 | tail -1
hdfs --daemon stop secondarynamenode 2>&1 | tail -1
hdfs --daemon stop namenode 2>&1 | tail -1
EOF
}

echo "stop datanodes"
run team-02-01 "$(stop_dn)" || true
run team-02-00 "$(stop_dn)" || true
run team-02-nn "$(stop_nn)" || true

echo "остались процессы dpe_sevinch? (должно быть пусто)"
for HOST in team-02-nn team-02-00 team-02-01; do
  echo "--> $HOST"
  ssh -i ~/.ssh/team_internal -o ConnectTimeout=8 "team@$HOST" \
    "ps -eo user,pid,cmd | grep dpe_sevinch | grep -E 'NameNode|DataNode|SecondaryNameNode' | grep -v grep || echo '  none'"
done
echo "DONE"