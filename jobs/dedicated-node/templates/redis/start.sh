#!/usr/bin/env bash
set -e

source /var/vcap/jobs/dedicated-node/config/envs.sh

/sbin/start-stop-daemon \
  --pidfile "$REDIS_PIDFILE_PATH" \
  --chuid vcap:vcap \
  --start \
  --exec /var/vcap/packages/redis/bin/redis-server -- \
  "$REDIS_CONFIG_PATH" \
  2>&1 | tee --append "$REDIS_LOG_PATH" | logger -s -t redis-ctl
