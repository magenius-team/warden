#!/usr/bin/env bash
[[ ! ${WARDEN_DIR} ]] && >&2 echo -e "\033[31mThis script is not intended to be run directly!\033[0m" && exit 1

source "${WARDEN_DIR}/utils/install.sh"
assertWardenInstall
assertDockerRunning

if (( ${#WARDEN_PARAMS[@]} == 0 )) || [[ "${WARDEN_PARAMS[0]}" == "help" ]]; then
  $WARDEN_BIN svc --help || exit $? && exit $?
fi

## allow return codes from sub-process to bubble up normally
trap '' ERR

## configure docker compose files
DOCKER_COMPOSE_ARGS=()

DOCKER_COMPOSE_ARGS+=("-f")
DOCKER_COMPOSE_ARGS+=("${WARDEN_DIR}/docker/docker-compose.yml")

if [[ -f "${WARDEN_HOME_DIR}/.env" ]]; then
    eval "$(sed 's/\r$//g' < "${WARDEN_HOME_DIR}/.env" | grep "^WARDEN_")"
fi

export WARDEN_DOCKER_SOCK="${WARDEN_DOCKER_SOCK:-/var/run/docker.sock}"

## buggregator smtp service is enabled by default
WARDEN_MAIL_SERVICE="${WARDEN_MAIL_SERVICE:-buggregator}"
if [[ "$WARDEN_MAIL_SERVICE" == "mailpit" || "$WARDEN_MAIL_SERVICE" == "mailhog" ]]; then
    DOCKER_COMPOSE_ARGS+=("-f")
    DOCKER_COMPOSE_ARGS+=("${WARDEN_DIR}/docker/docker-compose.${WARDEN_MAIL_SERVICE}.yml")
fi

## add dnsmasq docker-compose
WARDEN_DNSMASQ_ENABLE="${WARDEN_DNSMASQ_ENABLE:-1}"
if [[ "$WARDEN_DNSMASQ_ENABLE" == "1" ]]; then
    DOCKER_COMPOSE_ARGS+=("-f")
    DOCKER_COMPOSE_ARGS+=("${WARDEN_DIR}/docker/docker-compose.dnsmasq.yml")
fi

WARDEN_PORTAINER_ENABLE="${WARDEN_PORTAINER_ENABLE:-0}"
if [[ "${WARDEN_PORTAINER_ENABLE}" == 1 ]]; then
    DOCKER_COMPOSE_ARGS+=("-f")
    DOCKER_COMPOSE_ARGS+=("${WARDEN_DIR}/docker/docker-compose.portainer.yml")
fi

## phpmyadmin is disabled by default
WARDEN_PHPMYADMIN_ENABLE="${WARDEN_PHPMYADMIN_ENABLE:-0}"
if [[ "${WARDEN_PHPMYADMIN_ENABLE}" == 1 ]]; then
    if [[ -d "${WARDEN_HOME_DIR}/etc/phpmyadmin/config.user.inc.php" ]]; then
        rm -rf ${WARDEN_HOME_DIR}/etc/phpmyadmin/config.user.inc.php
    fi
    if [[ ! -f "${WARDEN_HOME_DIR}/etc/phpmyadmin/config.user.inc.php" ]]; then
        mkdir -p "${WARDEN_HOME_DIR}/etc/phpmyadmin"
        touch ${WARDEN_HOME_DIR}/etc/phpmyadmin/config.user.inc.php
    fi
    DOCKER_COMPOSE_ARGS+=("-f")
    DOCKER_COMPOSE_ARGS+=("${WARDEN_DIR}/docker/docker-compose.phpmyadmin.yml")
fi

# elasticvue is disabled by default
WARDEN_ELASTICVUE_ENABLE=${WARDEN_ELASTICVUE_ENABLE:-0}
if [[ ${WARDEN_ELASTICVUE_ENABLE} -eq 1 ]]; then
    DOCKER_COMPOSE_ARGS+=("-f")
    DOCKER_COMPOSE_ARGS+=("${WARDEN_DIR}/docker/docker-compose.elasticvue.yml")
fi

## allow an additional docker-compose file to be loaded for global services
if [[ -f "${WARDEN_HOME_DIR}/docker-compose.yml" ]]; then
    DOCKER_COMPOSE_ARGS+=("-f")
    DOCKER_COMPOSE_ARGS+=("${WARDEN_HOME_DIR}/docker-compose.yml")
fi

## special handling when 'svc up' is run
if [[ "${WARDEN_PARAMS[0]}" == "up" ]]; then

    ## sign certificate used by global services (by default warden.test)
    if [[ -f "${WARDEN_HOME_DIR}/.env" ]]; then
        eval "$(grep "^WARDEN_SERVICE_DOMAIN" "${WARDEN_HOME_DIR}/.env")"
    fi

    WARDEN_SERVICE_DOMAIN="${WARDEN_SERVICE_DOMAIN:-warden.test}"
    if [[ ! -f "${WARDEN_SSL_DIR}/certs/${WARDEN_SERVICE_DOMAIN}.crt.pem" ]]; then
        "$WARDEN_BIN" sign-certificate "${WARDEN_SERVICE_DOMAIN}"
    fi

    if [[ ! -d "${WARDEN_HOME_DIR}/etc/traefik" ]]; then
        mkdir -p "${WARDEN_HOME_DIR}/etc/traefik"
    fi

    ## copy configuration files into location where they'll be mounted into containers from
    cp "${WARDEN_DIR}/config/traefik/traefik.yml" "${WARDEN_HOME_DIR}/etc/traefik/traefik.yml"

    ## generate dynamic traefik ssl termination configuration
    mkdir -p "${WARDEN_HOME_DIR}/etc/traefik/providers"
    cat > "${WARDEN_HOME_DIR}/etc/traefik/providers/dynamic.yml" <<-EOT
		tls:
		  stores:
		    default:
		      defaultCertificate:
		        certFile: /etc/ssl/certs/warden/${WARDEN_SERVICE_DOMAIN}.crt.pem
		        keyFile: /etc/ssl/certs/warden/${WARDEN_SERVICE_DOMAIN}.key.pem
		  certificates:
	EOT

    for cert in $(find "${WARDEN_SSL_DIR}/certs" -type f -name "*.crt.pem" | sed -E 's#^.*/ssl/certs/(.*)\.crt\.pem$#\1#'); do
        cat >> "${WARDEN_HOME_DIR}/etc/traefik/providers/dynamic.yml" <<-EOF
		    - certFile: /etc/ssl/certs/warden/${cert}.crt.pem
		      keyFile: /etc/ssl/certs/warden/${cert}.key.pem
		EOF
    done

    cat > "${WARDEN_HOME_DIR}/etc/traefik/providers/csp-merge.yml" <<-EOT
		http:
		  middlewares:
		    csp-merge:
		      plugin:
		        csp-merge:
		          domains:
		            - "*.test"
		          directives:
		            - default-src
		            - script-src
		            - style-src
		            - img-src
		            - font-src
		            - connect-src
		            - media-src
	EOT

    ## always execute svc up using --detach mode
    if ! (containsElement "-d" "$@" || containsElement "--detach" "$@"); then
        WARDEN_PARAMS=("${WARDEN_PARAMS[@]:1}")
        WARDEN_PARAMS=(up -d "${WARDEN_PARAMS[@]}")
    fi
fi

## pass ochestration through to docker compose
WARDEN_SERVICE_DIR=${WARDEN_DIR} ${DOCKER_COMPOSE_COMMAND} \
    --project-directory "${WARDEN_HOME_DIR}" -p warden \
    "${DOCKER_COMPOSE_ARGS[@]}" "${WARDEN_PARAMS[@]}" "$@"

## connect peered service containers to environment networks when 'svc up' is run
if [[ "${WARDEN_PARAMS[0]}" == "up" ]]; then
    for network in $(docker network ls -f label=dev.warden.environment.name --format {{.Name}}); do
        connectPeeredServices "${network}"
    done

    if [[ "${WARDEN_PHPMYADMIN_ENABLE}" == 1 ]]; then
        regeneratePMAConfig
    fi
fi
