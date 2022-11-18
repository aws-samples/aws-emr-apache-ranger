#!/bin/bash
set -euo pipefail
set -x

scripts_repo_path=$1
file_name=enable-glue-catalog-support.sh
#file_name=presto-kerberos-ba.sh
ranger_glue_script_setup_location=/tmp/$file_name

aws s3 cp ${scripts_repo_path}/scripts/$file_name ${ranger_glue_script_setup_location}


sudo sed "s|null &|null \&\& sudo sh ${ranger_glue_script_setup_location} >> \$STDOUT_LOG 2>> \$STDERR_LOG \&\n|" /usr/share/aws/emr/node-provisioner/bin/provision-node > ~/provision-node.new
sudo cp ~/provision-node.new /usr/share/aws/emr/node-provisioner/bin/provision-node
