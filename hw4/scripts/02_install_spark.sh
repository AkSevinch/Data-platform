#!/usr/bin/env bash
set -euo pipefail

LINUX_USER="dpe_sevinch"
DRIVER_HOST="team-02-nn"
SPARK_URL="https://archive.apache.org/dist/spark/spark-3.5.1/spark-3.5.1-bin-hadoop3.tgz"

INSTALL_SCRIPT=$(cat <<'INSTALL_EOF'
#!/usr/bin/env bash
set -euo pipefail
source ~/.dpe_env

SPARK_HOME="$DPE_BASE/dist/spark"
DOWNLOAD="$DPE_BASE/dist/downloads/spark-3.5.1-bin-hadoop3.tgz"
TMP="$DPE_BASE/tmp/hw4/spark-extract"

mkdir -p "$DPE_BASE/dist/downloads" "$DPE_BASE/tmp/hw4"

spark_version() {
  "$SPARK_HOME/bin/spark-submit" --version 2>&1 | awk '/version/{print $NF; exit}'
}

if [ -x "$SPARK_HOME/bin/spark-sql" ]; then
  echo "  Spark уже установлен: $(spark_version)"
  exit 0
fi

if [ -e "$SPARK_HOME" ]; then
  echo "  $SPARK_HOME существует, но не содержит bin/spark-sql; не удаляю автоматически"
  exit 1
fi

if [ ! -s "$DOWNLOAD" ]; then
  echo "  скачивание Spark 3.5.1 (~381 MB)"
  curl -fL --retry 3 -m 3600 -o "$DOWNLOAD.part" "SPARK_URL_PLACEHOLDER"
  mv "$DOWNLOAD.part" "$DOWNLOAD"
fi

[ "$(stat -c%s "$DOWNLOAD")" -gt 300000000 ] || {
  echo "  скачанный архив слишком мал: $(stat -c%s "$DOWNLOAD")"; exit 1;
}
tar tzf "$DOWNLOAD" >/dev/null

rm -rf "$TMP"
mkdir -p "$TMP"
tar xzf "$DOWNLOAD" -C "$TMP"
mv "$TMP/spark-3.5.1-bin-hadoop3" "$SPARK_HOME"
rm -rf "$TMP"

[ -x "$SPARK_HOME/bin/spark-sql" ] || { echo "  нет $SPARK_HOME/bin/spark-sql"; exit 1; }
echo "  установлен: $(spark_version)"
echo "  размер: $(du -sh "$SPARK_HOME" | awk '{print $1}')"
INSTALL_EOF
)

INSTALL_SCRIPT=${INSTALL_SCRIPT/SPARK_URL_PLACEHOLDER/$SPARK_URL}

echo "--> $DRIVER_HOST (Spark 3.5.1)"
ssh -i ~/.ssh/team_internal -o StrictHostKeyChecking=accept-new -o ConnectTimeout=8 \
  "team@$DRIVER_HOST" "sudo -iu $LINUX_USER bash -s" <<< "$INSTALL_SCRIPT"

echo "DONE"
