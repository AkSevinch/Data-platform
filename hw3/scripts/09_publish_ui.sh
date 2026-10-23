#!/usr/bin/env bash
set -euo pipefail

EDGE="${EDGE:-team@111.88.128.191}"
KEY="${SSH_KEY:-$HOME/.ssh/id_ed25519}"
MARKER="21051:10.2.0.12:21051"

[ -f "$KEY" ] || { echo "нет ключа: $KEY (задай SSH_KEY=путь)"; exit 1; }

if ! curl -s -m 2 -o /dev/null "http://localhost:21051/"; then
  echo "открываю туннель через $EDGE"
  ssh -i "$KEY" -f -N -o ExitOnForwardFailure=yes -o ConnectTimeout=10 \
    -L 21051:10.2.0.12:21051 "$EDGE" \
    || { echo "не удалось открыть туннель"; exit 1; }
  sleep 2
fi

CODE=""
for i in 1 2 3; do
  CODE=$(curl -s -m 3 -o /dev/null -w '%{http_code}' "http://localhost:21051/" || echo 000)
  { [ "$CODE" = "200" ] || [ "$CODE" = "302" ]; } && break
  sleep 1
done

printf "%-28s %s\n" "ДЕМОН" "URL"
if [ "$CODE" = "200" ] || [ "$CODE" = "302" ]; then
  printf "%-28s %s  OK\n" "HiveServer2 Web UI" "http://localhost:21051/"
  echo
  echo "все UI доступны из браузера"
  echo "остановить туннель: pkill -f \"$MARKER\""
else
  printf "%-28s %s  FAIL(%s)\n" "HiveServer2 Web UI" "http://localhost:21051/" "$CODE"
  echo "проверь, что Hive запущен (hw3/scripts/06_verify.sh)"
  exit 1
fi
