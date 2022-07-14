#!/bin/bash
set -euo pipefail
set -x

HUE_INI='/etc/hue/conf.empty/hue.ini'

## Update Trino user mapping
sudo sed -i "s|http-server.authentication.krb5.user-mapping.pattern.*|http-server.authentication.krb5.user-mapping.pattern=(.*)(/)(.*)|g" /etc/trino/conf/config.properties

# Update Hue.ini
sudo sed  -i 's/"io.trino.jdbc.TrinoDriver"/& , "user" : "", "password" : "" /' /etc/hue/conf/hue.ini

sudo /opt/aws/puppet/bin/puppet apply -e 'service { "trino-server": ensure => false, }'
sudo /opt/aws/puppet/bin/puppet apply -e 'service { "trino-server": ensure => true, }'

sudo systemctl restart hue

exit 0
