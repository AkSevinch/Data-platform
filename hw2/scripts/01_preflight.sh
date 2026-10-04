#!/usr/bin/env bash
set -euo pipefail

NAME="sevinch"
LINUX_USER="dpe_sevinch"
BASE="/srv/dpe/$NAME"
HW="hw2"
NODES=("team-02-nn" "team-02-00" "team-02-01")
YARN_PORTS=(21030 21031 21032 21033 21088 21040 21041 21042 21045 21120 21888 21188)

for HOST in "${NODES[@]}"; do
  echo "--> $HOST"
  ssh -i ~/.ssh/team_internal -o ConnectTimeout=8 "team@$HOST" "
    sudo mkdir -p '$BASE/conf/$HW' '$BASE/logs/$HW' '$BASE/pids/$HW' \
      '$BASE/tmp/$HW/nm-local' '$BASE/logs/$HW/nm' '$BASE/homeworks/$HW'
    sudo chown -R $LINUX_USER:$LINUX_USER '$BASE/conf/$HW' '$BASE/logs/$HW' \
      '$BASE/pids/$HW' '$BASE/tmp/$HW' '$BASE/homeworks/$HW'
    busy=''
    for p in ${YARN_PORTS[*]}; do
      ss -ltn 2>/dev/null | grep -q \":\$p \" && busy=\"\$busy \$p\"
    done
    if [ -n \"\$busy\" ]; then echo \"  ЗАНЯТЫ порты:\$busy\"; exit 1; fi
    echo '  порты 21030-21888: свободны, каталоги готовы'
  "
done

echo "--> HDFS жив?"
run_nn() {
  ssh -i ~/.ssh/team_internal -o ConnectTimeout=8 team@team-02-nn \
    "sudo -iu $LINUX_USER bash -s" <<< "$1"
}
run_nn 'source ~/.dpe_env; hdfs dfsadmin -report 2>/dev/null | grep -E "Live datanodes"' \
  || { echo "  HDFS не отвечает — сначала запусти ДЗ1: bash scripts/05_start.sh"; exit 1; }

if ! run_nn 'source ~/.dpe_env; cat "$DPE_BASE/PORTS.md" 2>/dev/null' | grep -q "HW2"; then
  echo "--> запись портов HW2 в PORTS.md"
  run_nn 'source ~/.dpe_env; cat >> "$DPE_BASE/PORTS.md" <<EOF

## HW2 YARN cluster (sevinch range 21000-21999)
- rm_scheduler_rpc: 21030
- rm_resource_tracker_rpc: 21031
- rm_client_rpc: 21032
- rm_admin_rpc: 21033
- rm_webapp: 21088
- nm_localizer: 21040
- nm_rpc: 21041
- nm_webapp: 21042
- nm_shuffle: 21045
- jobhistory_rpc: 21120
- jobhistory_webapp: 21888
- timeline_webapp: 21188
EOF'
fi

echo "DONE"
