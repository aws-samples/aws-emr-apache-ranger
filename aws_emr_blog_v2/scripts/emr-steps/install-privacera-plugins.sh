#!/bin/bash
set -euo pipefail
set -x
#Variables
if [[ -n "$JAVA_HOME" ]] && [[ -x "$JAVA_HOME/bin/java" ]];  then
  echo "found java executable in JAVA_HOME"
else
  export JAVA_HOME=/usr/lib/jvm/java-openjdk
fi

privacera_plugin_url=$1

cd /tmp
wget $privacera_plugin_url
chmod +x ./privacera_emr.sh
sudo ./privacera_emr.sh
