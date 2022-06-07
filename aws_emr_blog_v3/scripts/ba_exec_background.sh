#!/bin/bash

script="$1"
tmp_script="/tmp/script_$(date +"%s")"

aws s3 cp ${script} ${tmp_script}
chmod +x ${tmp_script}
nohup ${tmp_script} &>/dev/null &
