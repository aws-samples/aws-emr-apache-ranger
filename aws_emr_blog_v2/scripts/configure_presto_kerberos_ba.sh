#!/bin/bash

scripts_repo_path=$1

kdc_password=$2
presto_script_setup_location=/tmp/configure_presto_kerberos.sh

aws s3 cp ${scripts_repo_path}/scripts/configure_presto_kerberos.sh ${presto_script_setup_location}


sudo sed "s|null &|null \&\& sudo sh ${presto_script_setup_location} ${kdc_password} >> \$STDOUT_LOG 2>> \$STDERR_LOG \&\n|" /usr/share/aws/emr/node-provisioner/bin/provision-node > ~/provision-node.new
sudo cp ~/provision-node.new /usr/share/aws/emr/node-provisioner/bin/provision-node
