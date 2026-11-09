#!/usr/bin/env bash
set -euo pipefail

LINUX_USER="dpe_sevinch"
DRIVER_HOST="team-02-nn"
PREFECT_VERSION="3.9.2"

install_script=$(cat <<'INSTALL_EOF'
#!/usr/bin/env bash
set -euo pipefail
source ~/.dpe_env

VENV="$DPE_BASE/venv/hw5"
GETPIP="$DPE_BASE/tmp/hw5/get-pip.py"
PIP_CACHE="$DPE_BASE/tmp/hw5/pip-cache"
export PIP_CACHE_DIR="$PIP_CACHE"
export PREFECT_HOME="$DPE_BASE/data/hw5/prefect"
export PREFECT_SERVER_ANALYTICS_ENABLED=false

mkdir -p "$DPE_BASE/tmp/hw5" "$PREFECT_HOME" "$(dirname "$VENV")"

if [ -x "$VENV/bin/prefect" ]; then
  current=$("$VENV/bin/prefect" version 2>/dev/null | head -1 || true)
  if echo "$current" | grep -q "PREFECT_VERSION_PLACEHOLDER"; then
    echo "  Prefect уже установлен: $current"
    exit 0
  fi
fi

if [ ! -x "$VENV/bin/python" ]; then
  echo "  создание venv без pip"
  python3 -m venv --without-pip "$VENV"
fi

if [ ! -x "$VENV/bin/pip" ]; then
  echo "  bootstrap pip"
  curl -fL --retry 3 -m 600 -o "$GETPIP" https://bootstrap.pypa.io/get-pip.py
  "$VENV/bin/python" "$GETPIP"
fi

echo "  установка Prefect PREFECT_VERSION_PLACEHOLDER"
"$VENV/bin/pip" install --no-cache-dir "prefect==PREFECT_VERSION_PLACEHOLDER"
"$VENV/bin/prefect" version
"$VENV/bin/prefect" version 2>/dev/null | grep -q "PREFECT_VERSION_PLACEHOLDER"
INSTALL_EOF
)

install_script=${install_script//PREFECT_VERSION_PLACEHOLDER/$PREFECT_VERSION}

echo "--> $DRIVER_HOST (Prefect $PREFECT_VERSION)"
ssh -i ~/.ssh/team_internal -o StrictHostKeyChecking=accept-new -o ConnectTimeout=8 \
  "team@$DRIVER_HOST" "sudo -iu $LINUX_USER bash -s" <<< "$install_script"

echo "DONE"
