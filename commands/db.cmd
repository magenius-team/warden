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
DB_CONTAINER=$("${WARDEN_BIN}" env ps -q db)
if [[ ! ${DB_CONTAINER} ]]; then
    fatal "No container found for db service."
fi

DB_ENV_PREFIX="MYSQL_"
if [[ ${DB_DISTRIBUTION:-mariadb} = "mariadb" ]]; then
    DB_ENV_PREFIX="MARIADB_"
fi

## Docker environment values are data, never shell code. Use NUL-delimited
## records so values containing spaces, quotes, or newlines remain intact.
DB_ENV_FILE="$(mktemp)" || fatal "Could not create a temporary database environment file."
if ! docker container inspect "${DB_CONTAINER}" --format '{{range .Config.Env}}{{printf "%s\x00" .}}{{end}}' > "${DB_ENV_FILE}"; then
    rm -f "${DB_ENV_FILE}"
    fatal "Could not inspect db service container."
fi

unset DB_USER DB_PASSWORD DB_DATABASE DB_ROOT_PASSWORD
while IFS= read -r -d '' record; do
    [[ "${record}" != *=* ]] && continue
    key="${record%%=*}"
    value="${record#*=}"
    case "${key}" in
        "${DB_ENV_PREFIX}USER") DB_USER="${value}" ;;
        "${DB_ENV_PREFIX}PASSWORD") DB_PASSWORD="${value}" ;;
        "${DB_ENV_PREFIX}DATABASE") DB_DATABASE="${value}" ;;
        "${DB_ENV_PREFIX}ROOT_PASSWORD") DB_ROOT_PASSWORD="${value}" ;;
    esac
done < "${DB_ENV_FILE}"
rm -f "${DB_ENV_FILE}"

if [[ -z "${DB_USER+x}" || -z "${DB_PASSWORD+x}" || -z "${DB_DATABASE+x}" ]]; then
    fatal "Could not read database credentials from db service container."
fi

## sub-command execution
case "${WARDEN_PARAMS[0]}" in
    connect)
        COMMAND=mysql
        if [[ ${DB_DISTRIBUTION:-mariadb} = "mariadb" ]] && [[ $(version "${DB_DISTRIBUTION_VERSION}") -ge $(version '11.0') ]]; then
            COMMAND=mariadb
        fi
        "$WARDEN_BIN" env exec db \
            env MYSQL_PWD="${DB_PASSWORD}" \
            ${COMMAND} -u"${DB_USER}" --database="${DB_DATABASE}" "${WARDEN_PARAMS[@]:1}" "$@"
        ;;
    import)
        COMMAND=mysql
        if [[ ${DB_DISTRIBUTION:-mariadb} = "mariadb" ]] && [[ $(version "${DB_DISTRIBUTION_VERSION}") -ge $(version '11.0') ]]; then
            COMMAND=mariadb
        fi
        LC_ALL=C sed -E 's/DEFINER[ ]*=[ ]*`[^`]+`@`[^`]+`/DEFINER=CURRENT_USER/g' \
            | LC_ALL=C sed -E '/\@\@(GLOBAL\.GTID_PURGED|SESSION\.SQL_LOG_BIN)/d' \
            | "$WARDEN_BIN" env exec -T db \
            env MYSQL_PWD="${DB_PASSWORD}" \
            ${COMMAND} -u"${DB_USER}" --database="${DB_DATABASE}" "${WARDEN_PARAMS[@]:1}" "$@"
        ;;
    dump)
        COMMAND=mysqldump
        if [[ ${DB_DISTRIBUTION:-mariadb} = "mariadb" ]] && [[ $(version "${DB_DISTRIBUTION_VERSION}") -ge $(version '11.0') ]]; then
            COMMAND=mariadb-dump
        fi
        "$WARDEN_BIN" env exec -T db \
            env MYSQL_PWD="${DB_PASSWORD}" \
            ${COMMAND} -u"${DB_USER}" "${DB_DATABASE}" "${WARDEN_PARAMS[@]:1}" "$@"
        ;;
    upgrade)
            if [[ -z "${DB_ROOT_PASSWORD+x}" ]]; then
                fatal "Could not read database root password from db service container."
            fi

            if [[ ${DB_DISTRIBUTION:-mariadb} == "mysql" ]]; then
                upgradeCmd="mysql_upgrade"
            elif [[ ${DB_DISTRIBUTION:-mariadb} == "mariadb" ]]; then
                upgradeCmd="mariadb-upgrade"
            else
                fatal "The upgrade command only supports MySQL and MariaDB installations."
                exit 1
            fi

            "$WARDEN_BIN" env exec -T db \
            env MYSQL_PWD="${DB_ROOT_PASSWORD}" \
            ${upgradeCmd}
        ;;
    *)
        fatal "The command \"${WARDEN_PARAMS[0]}\" does not exist. Please use --help for usage."
        ;;
esac
