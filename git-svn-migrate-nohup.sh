#!/bin/bash

log_out="log/$(date +%Y%m%d%H%M%S).nohup.log"
mkdir -p log
nohup ./git-svn-migrate.sh "$@" > ${log_out} &
sleep 1
tail -f ${log_out}
