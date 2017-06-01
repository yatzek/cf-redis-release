#!/usr/bin/env bash
set -e

source /var/vcap/jobs/dedicated-node/config/envs.sh

/sbin/start-stop-daemon \
  --pidfile "$REDIS_PIDFILE_PATH" \
  --oknodo \
  --stop
