#!/bin/bash
set -euo pipefail
set -x
AWS_REGION=${1-'us-east-1'}
DEFAULT_EC2_REALM='EC2\.INTERNAL'
echo $(tr '[:upper:]' '[:lower:]' <<< "$AWS_REGION")
if [[ $(tr '[:upper:]' '[:lower:]' <<< "$AWS_REGION") = "us-east-1" ]]; then
  DEFAULT_EC2_REALM='EC2\.INTERNAL'
  echo "AWS region is us-east-1, will use EC2 realm as ec2.internal"
else
   DEFAULT_EC2_REALM='COMPUTE\.INTERNAL'
   echo "AWS region is NOT us-east-1, will use EC2 realm as compute.internal"
fi

livy_conf_file='/etc/livy/conf/livy.conf'

sudo sh -c "echo 'livy.server.auth.kerberos.name_rules = RULE:[1:\$1@\$0](.*@AWSEMR\.COM)s/@.*///L RULE:[2:\$1@\$0](.*@AWSEMR\.COM)s/@.*///L RULE:[2:\$1@\$0](.*@${DEFAULT_EC2_REALM})s/@.*///L' >> $livy_conf_file"

sudo /opt/aws/puppet/bin/puppet apply -e 'service { "livy-server": ensure => false, }'
sudo /opt/aws/puppet/bin/puppet apply -e 'service { "livy-server": ensure => true, }'

exit 0
