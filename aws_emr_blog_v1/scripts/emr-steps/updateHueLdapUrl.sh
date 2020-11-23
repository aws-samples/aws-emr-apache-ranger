#!/bin/bash
set -euo pipefail
set -x
ldap_ip_address=$1
sudo sed -i "s|ldap://.*[^']|ldap://$ldap_ip_address|g" /etc/puppet/hieradata/site.yaml
cd  /var/aws/emr/
sudo puppet apply --verbose -d --modulepath="bigtop-deploy/puppet/modules:/etc/puppet/modules" bigtop-deploy/puppet/manifests/site.pp -e 'include hue::server' 2>&1 | tee ~/puppet_apply.log
sudo puppet apply -e 'service { "hue": ensure => false, }'
sudo puppet apply -e 'service { "hue": ensure => true, }'