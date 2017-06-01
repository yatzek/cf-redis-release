#!/usr/bin/env bash

export REDIS_LOG_DIR=/var/vcap/sys/log/redis
export REDIS_LOG_PATH="${REDIS_LOG_DIR}/redis.log"

export RUN_DIR=/var/vcap/sys/run
export REDIS_PIDFILE_PATH="${RUN_DIR}/redis.pid"

export REDIS_DATA_DIR=/var/vcap/store/redis
export REDIS_CONFIG_PATH="${REDIS_DATA_DIR}/redis.conf"
