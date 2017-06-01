#!/usr/bin/env bash
set -e

source /var/vcap/jobs/dedicated-node/config/envs.sh

mkdir -p "$REDIS_AGENT_LOG_DIR"
chown vcap:vcap "$REDIS_AGENT_LOG_DIR"

mkdir -p "$REDIS_LOG_DIR"
chown vcap:vcap "$REDIS_LOG_DIR"

if [ ! -f "$REDIS_LOG_PATH" ]; then touch "$REDIS_LOG_PATH"; fi
chown vcap:vcap "$REDIS_LOG_PATH"

mkdir -p "$RUN_DIR"
chown vcap:vcap "$RUN_DIR"

mkdir -p "$REDIS_DATA_DIR"
chown vcap:vcap "$REDIS_DATA_DIR"

# recommended Redis system configurations
ulimit -n 10032
sysctl vm.overcommit_memory=1
