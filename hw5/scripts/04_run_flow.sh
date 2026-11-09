#!/usr/bin/env bash
set -euo pipefail

NAME="sevinch"
LINUX_USER="dpe_sevinch"
BASE="/srv/dpe/$NAME"
DRIVER_HOST="team-02-nn"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOCAL_OUT="$ROOT/homeworks"

mkdir -p "$LOCAL_OUT"

echo "--> $DRIVER_HOST (Prefect flow)"
set +e
ssh -i ~/.ssh/team_internal -o ConnectTimeout=8 "team@$DRIVER_HOST" \
  "sudo -iu $LINUX_USER bash -s" 2>&1 <<'EOF' | tee "$LOCAL_OUT/flow.log"
set -euo pipefail
source ~/.dpe_env
source "$DPE_BASE/conf/hw5/prefect.env"
source "$DPE_BASE/conf/hw5/spark-env.sh"
unset PREFECT_API_URL || true

VENV="$DPE_BASE/venv/hw5"
FLOW="$DPE_BASE/homeworks/hw5/flows/sales_flow.py"
LOG="$DPE_BASE/logs/hw5/flow.log"

[ -x "$VENV/bin/python" ] || { echo "  нет venv hw5, выполните 02_install_prefect.sh"; exit 1; }
[ -f "$FLOW" ] || { echo "  нет $FLOW, выполните 03_apply_config.sh"; exit 1; }
mkdir -p "$DPE_BASE/logs/hw5" "$DPE_BASE/tmp/hw5"

"$VENV/bin/python" "$FLOW" 2>&1 | tee "$LOG"
EOF
rc=${PIPESTATUS[0]}
set -e

copy_remote() {
  remote="$1"
  local="$2"
  ssh -i ~/.ssh/team_internal -o ConnectTimeout=8 "team@$DRIVER_HOST" \
    "sudo -iu $LINUX_USER cat '$remote'" > "$local" 2>/dev/null || true
}

copy_remote "$BASE/homeworks/hw5/flow_result.json" "$LOCAL_OUT/flow_result.json"
copy_remote "$BASE/homeworks/hw5/verify.txt" "$LOCAL_OUT/verify.txt"
copy_remote "$BASE/logs/hw5/spark_submit.log" "$LOCAL_OUT/spark_submit.log"

if [ "$rc" -ne 0 ]; then
  echo "Prefect flow завершился с ошибкой: $rc"
  exit "$rc"
fi

if [ -s "$LOCAL_OUT/flow_result.json" ]; then
  echo "FLOW_RESULT:"
  cat "$LOCAL_OUT/flow_result.json"
fi

echo "DONE"
