#!/bin/bash
set -euo pipefail
set -x

HUE_INI='/etc/hue/conf.empty/hue.ini'

sudo sed -i "s|http-server.authentication.krb5.user-mapping.pattern.*|#http-server.authentication.krb5.user-mapping.pattern=(.*)(/)(.*)|g" /etc/trino/conf/config.properties

## Update Trino user mapping
sudo tee -a /etc/trino/conf/config.properties > /dev/null <<EOT
http-server.authentication.krb5.user-mapping.file=etc/user-mapping.json
EOT

sudo tee -a /usr/lib/trino/etc/user-mapping.json > /dev/null <<EOT
{
    "rules": [
        {
            "pattern": "(.*)/(.*)(@.*)"
        },
        {
            "pattern": "(.*)(@.*)"
        }
    ]
}
EOT

# Update Hue.ini
sudo sed  -i 's/"io.trino.jdbc.TrinoDriver"/& , "user" : "", "password" : "" /' /etc/hue/conf/hue.ini

sudo /opt/aws/puppet/bin/puppet apply -e 'service { "trino-server": ensure => false, }'
sudo /opt/aws/puppet/bin/puppet apply -e 'service { "trino-server": ensure => true, }'

sudo systemctl restart hue

exit 0