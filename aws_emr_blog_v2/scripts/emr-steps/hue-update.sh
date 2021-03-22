#!/bin/bash

current_hostname=$(hostname -f)
emr_version=$1
presto_engine=$2
if [ -f "/opt/aws/puppet/bin/puppet" ]; then
  echo "Puppet found in path"
  puppet_cmd='/opt/aws/puppet/bin/puppet'
else
  puppet_cmd='puppet'
fi

if [ "$presto_engine" == "PrestoSQL" ]; then
  sudo sed -i "s|\"url\": \"jdbc:presto.*\"|\"url\": \"jdbc:presto://$current_hostname:8446/hive/default?SSL=true\&SSLTrustStorePath=/usr/lib/jvm/java/jre/lib/security/cacerts\&SSLTrustStorePassword=changeit\", \"driver\":\"io.prestosql.jdbc.PrestoDriver\", \"user\":\"\", \"password\":\"\"|g" /etc/hue/conf.empty/hue.ini
else
  sudo sed -i "s|\"url\": \"jdbc:presto.*\"|\"url\": \"jdbc:presto://$current_hostname:8446/hive/default?SSL=true\&SSLTrustStorePath=/usr/lib/jvm/java/jre/lib/security/cacerts\&SSLTrustStorePassword=changeit\", \"driver\":\"com.facebook.presto.jdbc.PrestoDriver\", \"user\":\"\", \"password\":\"\"|g" /etc/hue/conf.empty/hue.ini
fi


sudo ${puppet_cmd} apply -e 'service { "hue": ensure => false, }'
sudo ${puppet_cmd} apply -e 'service { "hue": ensure => true, }'
