#!/bin/bash
set -euo pipefail
set -x
if [[ -n "$JAVA_HOME" ]] && [[ -x "$JAVA_HOME/bin/java" ]];  then
  echo "found java executable in JAVA_HOME"
else
  export JAVA_HOME=/usr/lib/jvm/java-openjdk
fi
sudo -E bash -c 'echo $JAVA_HOME'
installpath=/usr/lib/ranger-pugins
ranger_server_fqdn=$1
default_domain=ec2.internal
hostname=`hostname -I | xargs`
hbase_server_fqdn=$hostname
ranger_policybucket=$2
#Update repo/policies
sudo rm -rf $installpath
sudo mkdir -p $installpath
sudo chmod -R 777 $installpath
cd $installpath
aws s3 cp $ranger_policybucket . --recursive --exclude "*" --include "*.json" --region us-east-1
sudo sed -i "s|emr_masternode|$hbase_server_fqdn|g" ranger-hbase-repo.json
curl -iv -u admin:admin -d @ranger-hbase-repo.json -H "Content-Type: application/json" -X POST http://$ranger_server_fqdn:6080/service/public/api/repository/
curl -iv -u admin:admin -d @ranger-hbase-policy-analyst1.json -H "Content-Type: application/json" -X POST http://$ranger_server_fqdn:6080/service/public/api/policy/
curl -iv -u admin:admin -d @ranger-hbase-policy-analyst2.json -H "Content-Type: application/json" -X POST http://$ranger_server_fqdn:6080/service/public/api/policy/
