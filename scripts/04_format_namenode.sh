#!/usr/bin/env bash
# 04_format_namenode.sh
# Форматирует NameNode НА STROGO team-02-nn после проверки dfs.namenode.name.dir.
# Выполнять с edge-ноды от пользователя team.
set -euo pipefail

LINUX_USER="dpe_sevinch"
BASE="/srv/dpe/sevinch"
HW="hw1"
CONF_DIR="$BASE/conf/$HW"
NN_HOST="team-02-nn"

echo "== Проверка, что dfs.namenode.name.dir указывает только на каталог участника =="
ssh -i ~/.ssh/team_internal -o ConnectTimeout=8 "team@$NN_HOST" \
  "sudo -iu $LINUX_USER bash -lc \"grep -A1 'dfs.namenode.name.dir' $CONF_DIR/hdfs-site.xml\""

echo "== Целевой путь: $BASE/data/$HW/namenode =="
read -r -p "Продолжить форматирование NameNode на $NN_HOST? y/N: " ANS
[ "${ANS:-n}" = "y" ] || { echo "отменено"; exit 1; }

ssh -i ~/.ssh/team_internal -o ConnectTimeout=8 "team@$NN_HOST" \
  "sudo -iu $LINUX_USER bash -lc 'hdfs namenode -format -force'"

echo "== После форматирования =="
ssh -i ~/.ssh/team_internal -o ConnectTimeout=8 "team@$NN_HOST" \
  "sudo -iu $LINUX_USER bash -lc 'ls -la $BASE/data/$HW/namenode/'"
echo "DONE"