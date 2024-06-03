#!/usr/bin/env bash
[[ ! ${WARDEN_DIR} ]] && >&2 echo -e "\033[31mThis script is not intended to be run directly!\033[0m" && exit 1

WARDEN_ENV_PATH="$(locateEnvPath)" || exit $?
loadEnvConfig "${WARDEN_ENV_PATH}" || exit $?
assertDockerRunning

if [[ ${WARDEN_DB:-1} -eq 0 ]]; then
  fatal "Database environment is not used (WARDEN_DB=0)."
fi

if (( ${#WARDEN_PARAMS[@]} == 0 )) || [[ "${WARDEN_PARAMS[0]}" == "help" ]]; then
  $WARDEN_BIN db --help || exit $? && exit $?
fi

## load connection information for the mysql service
DB_CONTAINER=$($WARDEN_BIN env ps -q db)
if [[ ! ${DB_CONTAINER} ]]; then
    fatal "No container found for db service."
fi

GREP_PREFIX="MYSQL_"
if [[ ${DB_DISTRIBUTION:-mariadb} = "mariadb" ]]; then
    GREP_PREFIX="MARIADB_"
fi

eval "$(
    docker container inspect ${DB_CONTAINER} --format '
        {{- range .Config.Env }}{{with split . "=" -}}
            {{- index . 0 }}='\''{{ range $i, $v := . }}{{ if $i }}{{ $v }}{{ end }}{{ end }}'\''{{println}}
        {{- end }}{{ end -}}
    ' | grep "^${GREP_PREFIX}"
)"

if [[ ${DB_DISTRIBUTION:-mariadb} = "mariadb" ]]; then
    DB_USER=${MARIADB_USER}
    DB_PASSWORD=${MARIADB_PASSWORD}
    DB_DATABASE=${MARIADB_DATABASE}
else
    DB_USER=${MYSQL_USER}
    DB_PASSWORD=${MYSQL_PASSWORD}
    DB_DATABASE=${MYSQL_DATABASE}
fi

## sub-command execution
case "${WARDEN_PARAMS[0]}" in
    connect)
        COMMAND=mysql
        if [[ ${DB_DISTRIBUTION:-mariadb} = "mariadb" ]] && [[ $(version "${DB_DISTRIBUTION_VERSION}") -ge $(version '11.0') ]]; then
            COMMAND=mariadb
        fi
        "$WARDEN_BIN" env exec db \
            ${COMMAND} -u"${DB_USER}" -p"${DB_PASSWORD}" --database="${DB_DATABASE}" "${WARDEN_PARAMS[@]:1}" "$@"
        ;;
    import)
        COMMAND=mysql
        if [[ ${DB_DISTRIBUTION:-mariadb} = "mariadb" ]] && [[ $(version "${DB_DISTRIBUTION_VERSION}") -ge $(version '11.0') ]]; then
            COMMAND=mariadb
        fi
        LC_ALL=C sed -E 's/DEFINER[ ]*=[ ]*`[^`]+`@`[^`]+`/DEFINER=CURRENT_USER/g' \
            | LC_ALL=C sed -E '/\@\@(GLOBAL\.GTID_PURGED|SESSION\.SQL_LOG_BIN)/d' \
            | "$WARDEN_BIN" env exec -T db \
            ${COMMAND} -u"${DB_USER}" -p"${DB_PASSWORD}" --database="${DB_DATABASE}" "${WARDEN_PARAMS[@]:1}" "$@"
        ;;
    dump)
        COMMAND=mysqldump
        if [[ ${DB_DISTRIBUTION:-mariadb} = "mariadb" ]] && [[ $(version "${DB_DISTRIBUTION_VERSION}") -ge $(version '11.0') ]]; then
            COMMAND=mariadb-dump
        fi
        "$WARDEN_BIN" env exec -T db \
            ${COMMAND} -u"${DB_USER}" -p"${DB_PASSWORD}" "${DB_DATABASE}" "${WARDEN_PARAMS[@]:1}" "$@"
        ;;
    *)
        fatal "The command \"${WARDEN_PARAMS[0]}\" does not exist. Please use --help for usage."
        ;;
esac
