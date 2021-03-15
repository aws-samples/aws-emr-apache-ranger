#!/bin/bash

ranger_server_fqdn=$1
ranger_version=$2
s3bucket=$3
project_version=${4-'2.0'}
emr_version=$5
presto_engine=$6
http_protocol=${7-'http'}
install_cloudwatch_agent_for_audit=${8-'false'}

#file_name=configure_presto_kerberos_for_hive.sh
file_name=install-hbase-ranger-plugin.sh
hbase_ranger_script_setup_location=/tmp/$file_name

aws s3 cp ${s3bucket}/${project_version}/scripts/emr-steps/$file_name ${hbase_ranger_script_setup_location}


sudo sed "s|null &|null \&\& sudo sh ${hbase_ranger_script_setup_location} ${ranger_server_fqdn} ${ranger_version} ${s3bucket} ${project_version} ${emr_version} ${presto_engine} ${http_protocol} ${install_cloudwatch_agent_for_audit} >> \$STDOUT_LOG 2>> \$STDERR_LOG \&\n|" /usr/share/aws/emr/node-provisioner/bin/provision-node > ~/provision-node.new
sudo cp ~/provision-node.new /usr/share/aws/emr/node-provisioner/bin/provision-node
