#!/bin/bash
set -euo pipefail
set -x

livy_conf_file='/etc/livy/conf/livy.conf'

sudo sh -c "echo 'livy.server.auth.kerberos.name_rules = RULE:[1:\$1@\$0](.*@AWSEMR\.COM)s/@.*///L RULE:[2:\$1@\$0](.*@AWSEMR\.COM)s/@.*///L RULE:[2:\$1@\$0](.*@EC2\.INTERNAL)s/@.*///L' >> $livy_conf_file"

sudo /opt/aws/puppet/bin/puppet apply -e 'service { "livy-server": ensure => false, }'
sudo /opt/aws/puppet/bin/puppet apply -e 'service { "livy-server": ensure => true, }'

exit 0
