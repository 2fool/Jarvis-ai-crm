#!/bin/bash

set -Eeo pipefail

# wait for the database to start
waitfordb() {
    # Skip database wait if DB_HOST is not set (for Railway deployment)
    if [ -z "${DB_HOST:-}" ]; then
        echo "DB_HOST not set, skipping database connection check"
        return 0
    fi

    HOST=${DB_HOST}
    PORT=${DB_PORT:-3306}
    echo "Connecting to ${HOST}:${PORT}"

    attempts=0
    max_attempts=30
    while [ $attempts -lt $max_attempts ]; do
        busybox nc -w 1 "${HOST}:${PORT}" && break
        echo "Waiting for ${HOST}:${PORT}..."
        sleep 1
        let "attempts=attempts+1"
    done

    if [ $attempts -eq $max_attempts ]; then
        echo "Unable to contact your database at ${HOST}:${PORT}"
        exit 1
    fi

    echo "Waiting for database to settle..."
    sleep 3
}

if expr "$1" : "apache" 1>/dev/null || [ "$1" = "php-fpm" ]; then

    MONICADIR=/var/www/html
    ARTISAN="php ${MONICADIR}/artisan"

    # Ensure storage directories are present
    STORAGE=${MONICADIR}/storage
    mkdir -p ${STORAGE}/logs
    mkdir -p ${STORAGE}/app/public
    mkdir -p ${STORAGE}/framework/views
    mkdir -p ${STORAGE}/framework/cache
    mkdir -p ${STORAGE}/framework/sessions
    chown -R www-data:www-data ${STORAGE}
    chmod -R g+rw ${STORAGE}

    if [ -z "${APP_KEY:-}" -o "$APP_KEY" = "ChangeMeBy32KeyLengthOrGenerated" ]; then
        ${ARTISAN} key:generate --no-interaction
    else
        echo "APP_KEY already set"
    fi

    # Run migrations only if database is available
    waitfordb
    if [ -n "${DB_HOST:-}" ]; then
        ${ARTISAN} monica:update --force -vv
    else
        echo "Database not configured, skipping migrations"
        # Generate storage link if it doesn't exist
        if [ ! -L "${MONICADIR}/public/storage" ]; then
            ${ARTISAN} storage:link
        fi
    fi

    if [ ! -f "${STORAGE}/oauth-public.key" -o ! -f "${STORAGE}/oauth-private.key" ]; then
        echo "Passport keys creation ..."
        ${ARTISAN} passport:keys
        ${ARTISAN} passport:client --personal --no-interaction
        echo "! Please be careful to backup $MONICADIR/storage/oauth-public.key and $MONICADIR/storage/oauth-private.key files !"
    fi

fi

exec "$@"
