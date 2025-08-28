#!/usr/bin/env bash
[[ ! ${WARDEN_DIR} ]] && >&2 echo -e "\033[31mThis script is not intended to be run directly!\033[0m" && exit 1

WARDEN_ENV_PATH="$(locateEnvPath)" || exit $?
loadEnvConfig "${WARDEN_ENV_PATH}" || exit $?
assertDockerRunning

if [[ ${WARDEN_S3:-0} -eq 0 ]]; then
  fatal "S3 environment is not used (WARDEN_S3=0)."
fi

# defaults variables
WARDEN_S3_ENDPOINT=http://localhost:9000
WARDEN_S3_ACCESS_KEY=minio
WARDEN_S3_SECRET_KEY=miniopwd
WARDEN_S3_ALIAS=local

# bucket: lowercase + '_' -> '-'
WARDEN_S3_BUCKET="$(echo "${WARDEN_ENV_NAME}" | tr '[:upper:]' '[:lower:]' | tr '_' '-')"
WARDEN_PROJECT_PATH_IN_MINIO=/var/www/html

die() { echo -e "\033[31mError:\033[0m $*" >&2; exit 1; }
info(){ echo "[s3] $*"; }

# init mc alias inside minio
mc_init_alias() {
  "$WARDEN_BIN" env exec minio mc alias set \
    "$WARDEN_S3_ALIAS" "$WARDEN_S3_ENDPOINT" "$WARDEN_S3_ACCESS_KEY" "$WARDEN_S3_SECRET_KEY" >/dev/null 2>&1 || true
}
mc() {
  "$WARDEN_BIN" env exec minio mc "$@"
}

cmd_console() {
  mc_init_alias
  "$WARDEN_BIN" env exec -ti minio /bin/sh -lc "
    mc alias set '$WARDEN_S3_ALIAS' '$WARDEN_S3_ENDPOINT' '$WARDEN_S3_ACCESS_KEY' '$WARDEN_S3_SECRET_KEY' >/dev/null
    echo 'MinIO client ready. Alias: $WARDEN_S3_ALIAS ($WARDEN_S3_ENDPOINT). Try: mc ls $WARDEN_S3_ALIAS'
    exec /bin/sh
  "
}

cmd_sync() {
  local LOCAL_DIR="$1"; shift || true
  local PREFIX="$1"; shift || true
  [[ -n "$LOCAL_DIR" && -n "$PREFIX" ]] || die "Usage: s3 sync <local-folder> <bucket-folder>"

  local SRC_PATH="${WARDEN_PROJECT_PATH_IN_MINIO%/}/${LOCAL_DIR}"
  echo "Source path: $SRC_PATH"
  mc_init_alias
  "$WARDEN_BIN" env exec minio test -d "$SRC_PATH" || die "Directory '$SRC_PATH' not found inside 'minio'. Check bind-mount."

  info "Sync '${SRC_PATH}' -> 's3://${WARDEN_S3_BUCKET}/${PREFIX}/' (overwrite)"
  mc ls "${WARDEN_S3_ALIAS}/${WARDEN_S3_BUCKET}" >/dev/null 2>&1 || mc mb "${WARDEN_S3_ALIAS}/${WARDEN_S3_BUCKET}"
  mc cp /dev/null "${WARDEN_S3_ALIAS}/${WARDEN_S3_BUCKET}/${PREFIX}/.init" >/dev/null 2>&1 || true
  mc mirror --overwrite "${SRC_PATH}/" "${WARDEN_S3_ALIAS}/${WARDEN_S3_BUCKET}/${PREFIX}/"
  info "DONE"
}

cmd_cp() {
  local SRC="$1"; shift || true
  local DST="$1"; shift || true
  [[ -n "$SRC" && -n "$DST" ]] || die "Usage: s3 cp <local-file> <bucket-file>"

  local SRC_PATH="${WARDEN_PROJECT_PATH_IN_MINIO%/}/${SRC}"
  mc_init_alias
  "$WARDEN_BIN" env exec minio test -f "$SRC_PATH" || die "File '$SRC_PATH' not found inside 'minio'."
  info "cp '${SRC_PATH}' -> 's3://${WARDEN_S3_BUCKET}/${DST}'"
  mc cp "${SRC_PATH}" "${WARDEN_S3_ALIAS}/${WARDEN_S3_BUCKET}/${DST}"
}

cmd_rm() {
  local KEY="$1"; shift || true
  [[ -n "$KEY" ]] || die "Usage: s3 rm <bucket-file>"
  mc_init_alias
  info "rm 's3://${WARDEN_S3_BUCKET}/${KEY}'"
  mc rm -r --force "${WARDEN_S3_ALIAS}/${WARDEN_S3_BUCKET}/${KEY}"
}

if [[ $# -eq 0 && -n "${WARDEN_PARAMS[*]}" ]]; then
  set -- "${WARDEN_PARAMS[@]}"
fi

subcmd="${1:-console}"
shift || true

case "${subcmd}" in
  sync) cmd_sync "$@" ;;
  cp) cmd_cp "$@" ;;
  rm) cmd_rm "$@" ;;
  *) cmd_console ;;
esac
