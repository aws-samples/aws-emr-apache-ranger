#!/bin/bash
set -euo pipefail
set -x
#Variables
if [[ -n "$JAVA_HOME" ]] && [[ -x "$JAVA_HOME/bin/java" ]];  then
  echo "found java executable in JAVA_HOME"
else
  export JAVA_HOME=/usr/lib/jvm/java-openjdk
fi
sudo -E bash -c 'echo $JAVA_HOME'
installpath=/usr/lib/ranger-pugins
ranger_server_fqdn=$1
ranger_policybucket=$2
http_protocol=$3
ranger_version=$4
ranger_admin_password=$5
default_domain=ec2.internal
hostname=`hostname -I | xargs`
hdfs_namenode_fqdn=$hostname
hive_server2_fqdn=$hostname

if [ "$http_protocol" == "https" ]; then
  RANGER_HTTP_URL=https://$ranger_server_fqdn:6182
  SOLR_HTTP_URL=https://$ranger_server_fqdn:8983
else
  RANGER_HTTP_URL=http://$ranger_server_fqdn:6080
  SOLR_HTTP_URL=http://$ranger_server_fqdn:8984
fi

#Update repo/policies
sudo rm -rf $installpath
sudo mkdir -p $installpath
sudo chmod -R 777 $installpath
cd $installpath
aws s3 cp $ranger_policybucket . --recursive --exclude "*" --include "*.json" --region us-east-1


for i in `find . -name "ranger-*-policy-*.json" -type f`; do
    file_name=`echo "$i" | cut -c 3-`
    echo "$file_name"
    curl -iv --insecure -u admin:$ranger_admin_password -d @$file_name -H "Content-Type: application/json" -X POST $RANGER_HTTP_URL/service/public/v2/api/policy/apply || true
done
