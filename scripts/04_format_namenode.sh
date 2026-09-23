#!/usr/bin/env bash
# форматирует NameNode на team-02-nn после проверки dfs.namenode.name.dir
set -euo pipefail

LINUX_USER="dpe_sevinch"
BASE="/srv/dpe/sevinch"
HW="hw1"
CONF_DIR="$BASE/conf/$HW"
NN_HOST="team-02-nn"

echo "проверка, что dfs.namenode.name.dir указывает только на каталог участника"
ssh -i ~/.ssh/team_internal -o ConnectTimeout=8 "team@$NN_HOST" \
  "sudo -iu $LINUX_USER bash -lc \"grep -A1 'dfs.namenode.name.dir' $CONF_DIR/hdfs-site.xml\""

echo "целевой путь: $BASE/data/$HW/namenode"
read -r -p "Продолжить форматирование NameNode на $NN_HOST? y/N: " ANS
[ "${ANS:-n}" = "y" ] || { echo "отменено"; exit 1; }

ssh -i ~/.ssh/team_internal -o ConnectTimeout=8 "team@$NN_HOST" \
  "sudo -iu $LINUX_USER bash -lc 'hdfs namenode -format -force'"

echo "после форматирования"
ssh -i ~/.ssh/team_internal -o ConnectTimeout=8 "team@$NN_HOST" \
  "sudo -iu $LINUX_USER bash -lc 'ls -la $BASE/data/$HW/namenode/'"
echo "DONE"