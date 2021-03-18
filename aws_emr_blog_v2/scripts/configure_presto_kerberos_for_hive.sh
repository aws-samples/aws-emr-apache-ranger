#!/bin/bash

kdc_password=$1
emr_domain=EC2.INTERNAL
presto_engine=$2

isMasterInstance=$(cat /mnt/var/lib/info/instance.json | jq '.isMaster')

#if [ "${isMasterInstance}" == "true" ];
#then
#sudo yum -y install krb5-server krb5-libs
sudo kadmin -w "$kdc_password" -p kadmin/admin -q "addprinc -randkey presto/$(hostname -f)@${emr_domain}"
sudo kadmin -w "$kdc_password" -p kadmin/admin -q "xst -k /etc/presto.keytab presto/$(hostname -f)@${emr_domain}"

sudo chown presto:presto /etc/presto.keytab

#Append to /etc/presto/conf/catalog/hive.properties

sudo tee -a /etc/presto/conf/catalog/hive.properties > /dev/null <<EOT
hive.metastore.authentication.type = KERBEROS
hive.metastore.client.principal = presto/_HOST@${emr_domain}
hive.metastore.client.keytab  =  /etc/presto.keytab
hive.metastore.service.principal = hive/_HOST@${emr_domain}
hive.hdfs.authentication.type = KERBEROS
hive.hdfs.presto.principal = presto/_HOST@${emr_domain}
hive.hdfs.presto.keytab = /etc/presto.keytab
EOT
if [ "$presto_engine" == "Presto" ]; then
sudo tee -a /etc/presto/conf/catalog/hive.properties > /dev/null <<EOT
hive.hdfs.wire-encryption.enabled = true
EOT
fi
sudo stop presto-server
sudo start presto-server

#else
#  echo "Slave instance. Doing nothing..."
#fi
