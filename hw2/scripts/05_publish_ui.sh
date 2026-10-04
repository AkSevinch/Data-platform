#!/usr/bin/env bash
set -euo pipefail

EDGE="${EDGE:-team@111.88.128.191}"
KEY="${SSH_KEY:-$HOME/.ssh/id_ed25519}"
MARKER="21970:10.2.0.11:21970"

# локальный порт : удаленный хост : удаленный порт : название демона
FORWARDS=(
  "21970:10.2.0.11:21970:NameNode"
  "21968:10.2.0.11:21968:SecondaryNameNode"
  "21964:10.2.0.11:21964:DataNode (team-02-nn)"
  "21965:10.2.0.12:21964:DataNode (team-02-00)"
  "21966:10.2.0.13:21964:DataNode (team-02-01)"
  "21088:10.2.0.11:21088:ResourceManager"
  "21042:10.2.0.11:21042:NodeManager (team-02-nn)"
  "21043:10.2.0.12:21042:NodeManager (team-02-00)"
  "21044:10.2.0.13:21042:NodeManager (team-02-01)"
  "21888:10.2.0.11:21888:JobHistory"
  "21188:10.2.0.11:21188:Timeline"
)

[ -f "$KEY" ] || { echo "нет ключа: $KEY (задай SSH_KEY=путь)"; exit 1; }

if ! curl -s -m 2 -o /dev/null "http://localhost:21970/"; then
  echo "открываю туннели через $EDGE"
  ARGS=()
  for F in "${FORWARDS[@]}"; do
    L="${F%%:*}"
    R="${F#*:}"
    ARGS+=(-L "$L:${R%:*}")
  done
  ssh -i "$KEY" -f -N -o ExitOnForwardFailure=yes -o ConnectTimeout=10 "${ARGS[@]}" "$EDGE" \
    || { echo "не удалось открыть туннели"; exit 1; }
  sleep 2
fi

echo
printf "%-46s %s\n" "ДЕМОН" "URL"
FAILED=0
for F in "${FORWARDS[@]}"; do
  L="${F%%:*}"; REST="${F#*:}"; NAME="${REST##*:}"
  CODE=""
  for i in 1 2 3; do
    CODE=$(curl -s -m 3 -o /dev/null -w '%{http_code}' "http://localhost:$L/" || echo 000)
    [ "$CODE" = "200" ] || [ "$CODE" = "302" ] && break
    sleep 1
  done
  URL="http://localhost:$L/"
  if [ "$CODE" = "200" ] || [ "$CODE" = "302" ]; then
    printf "%-46s %s  OK\n" "$NAME" "$URL"
  else
    printf "%-46s %s  FAIL(%s)\n" "$NAME" "$URL" "$CODE"
    FAILED=1
  fi
done

echo
if [ "$FAILED" = 1 ]; then
  echo "есть FAIL — проверь, что кластер запущен (hw2/scripts/04_verify.sh)"
else
  echo "все UI доступны из браузера"
  echo "остановить туннели: pkill -f \"$MARKER\""
fi
