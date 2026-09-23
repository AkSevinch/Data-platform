#!/usr/bin/env bash
# 05_start.sh
# Запускает демоны кластера HDFS поузлово от пользователя dpe_sevinch.
# Выполнять с edge-ноды от пользователя team.
set -euo pipefail

NN="team-02-nn"

run() { # run <host> <script>
  ssh -i ~/.ssh/team_internal -o ConnectTimeout=8 "team@$1" \
    "sudo -iu dpe_sevinch bash -s" <<< "$2"
}

start_nn() {
cat <<'EOF'
source ~/.dpe_env
hdfs --daemon start namenode 2>&1 | tail -1
sleep 3
hdfs --daemon start secondarynamenode 2>&1 | tail -1
sleep 2
hdfs --daemon start datanode 2>&1 | tail -1
EOF
}

start_dn() {
cat <<'EOF'
source ~/.dpe_env
hdfs --daemon start datanode 2>&1 | tail -1
EOF
}

echo "== team-02-nn: namenode + secondarynamenode + datanode =="
run "$NN" "$(start_nn)"
echo "== team-02-00: datanode =="
run team-02-00 "$(start_dn)"
echo "== team-02-01: datanode =="
run team-02-01 "$(start_dn)"

echo "DONE. Проверка: bash scripts/07_verify.sh"