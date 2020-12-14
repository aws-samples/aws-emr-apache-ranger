#!/bin/bash
set -euo pipefail
set -x
#Variables
if [[ -n "$JAVA_HOME" ]] && [[ -x "$JAVA_HOME/bin/java" ]];  then
  echo "found java executable in JAVA_HOME"
else
  export JAVA_HOME=/usr/lib/jvm/java-openjdk
fi
sudo -E bash -c 'echo $JAVA_HOME'
installpath=/usr/lib/ranger
ranger_ip=$1

ranger_fqdn=$(nslookup ${ranger_ip} | grep "name" | awk '{print $4}' | sed 's/.$//')
#mysql_jar_location=http://central.maven.org/maven2/mysql/mysql-connector-java/5.1.39/mysql-connector-java-5.1.39.jar
mysql_jar=mysql-connector-java-5.1.39.jar
ranger_version=$2
s3bucket=$3
install_cloudwatch_agent_for_audit=$4
ranger_download_version=0.5
if [ "$ranger_version" == "2.0" ]; then
   ranger_download_version=2.1.0-SNAPSHOT
elif [ "$ranger_version" == "1.0" ]; then
   ranger_download_version=1.0.1
elif [ "$ranger_version" == "0.7" ]; then
   ranger_download_version=0.7.1
elif [ "$ranger_version" == "0.6" ]; then
   ranger_download_version=0.6.1
else
   ranger_download_version=0.5
fi

ranger_s3bucket=$s3bucket/ranger/ranger-$ranger_download_version
ranger_hdfs_plugin=ranger-$ranger_download_version-hdfs-plugin

## Cert configuration
certs_s3_location=${s3bucket}/emr-tls/
certs_path="/tmp/certs"

ranger_agents_certs_path="${certs_path}/ranger-agents-certs"
ranger_server_certs_path="${certs_path}/ranger-server-certs"
solr_certs_path="${certs_path}/solr-client-certs"

truststore_ranger_server_alias="rangerServerTrust"
truststore_solr_alias="solrtrust"
truststore_password="changeit"
truststore_location="/etc/hadoop/conf/ranger-plugin-truststore.jks"

keystore_alias="rangerAgent"
keystore_password="changeit"
keystore_location="/etc/hadoop/conf/ranger-plugin-keystore.jks"

#Download certs
sudo rm -rf ${certs_path}
sudo rm -rf ${truststore_location}
sudo rm -rf ${keystore_location}

mkdir ${certs_path}
aws s3 sync ${certs_s3_location} ${certs_path}

mkdir ${ranger_agents_certs_path}
mkdir ${ranger_server_certs_path}
mkdir ${solr_certs_path}

unzip ${ranger_agents_certs_path}.zip -d ${ranger_agents_certs_path}
unzip ${ranger_server_certs_path}.zip -d ${ranger_server_certs_path}
unzip ${solr_certs_path}.zip -d ${solr_certs_path}

#Setup RangerAgents Keystore

openssl pkcs12 -export -in ${ranger_agents_certs_path}/certificateChain.pem -inkey ${ranger_agents_certs_path}/privateKey.pem -chain -CAfile ${ranger_agents_certs_path}/trustedCertificates.pem -name ${keystore_alias} -out ${ranger_agents_certs_path}/keystore.p12 -password pass:${keystore_password}
keytool -delete -alias ${keystore_alias} -keystore ${keystore_location} -storepass ${keystore_password} -noprompt || true
sudo keytool -importkeystore -deststorepass ${keystore_password} -destkeystore ${keystore_location} -srckeystore ${ranger_agents_certs_path}/keystore.p12 -srcstoretype PKCS12 -srcstorepass ${keystore_password}
sudo chmod 444 ${keystore_location}

#Setup Truststore - add RangerServer cert
sudo keytool -delete -alias ${truststore_ranger_server_alias} -keystore ${truststore_location} -storepass ${truststore_password} -noprompt || true
sudo keytool -import -file ${ranger_server_certs_path}/trustedCertificates.pem -alias ${truststore_ranger_server_alias} -keystore ${truststore_location} -storepass ${truststore_password} -noprompt

#Setup Truststore - add SOLR cert
sudo keytool -delete -alias ${truststore_solr_alias} -keystore ${truststore_location} -storepass ${truststore_password} -noprompt || true
sudo keytool -import -file ${solr_certs_path}/trustedCertificates.pem -alias ${truststore_solr_alias} -keystore ${truststore_location} -storepass ${truststore_password} -noprompt

#cleanup
rm -rf ${certs_path}

#Setup
sudo rm -rf $installpath
sudo rm -rf /etc/ranger/ || true
sudo mkdir -p $installpath/hadoop
sudo chmod -R 777 $installpath
cd $installpath
#wget $mysql_jar_location
aws s3 cp $ranger_s3bucket/$mysql_jar . --region us-east-1
aws s3 cp $ranger_s3bucket/$ranger_hdfs_plugin.tar.gz . --region us-east-1
mkdir $ranger_hdfs_plugin
tar -xvf $ranger_hdfs_plugin.tar.gz -C $ranger_hdfs_plugin --strip-components=1
cd $installpath/$ranger_hdfs_plugin


## Updates for new Ranger
mkdir -p /usr/lib/ranger/hadoop/etc
sudo ln -s /etc/hadoop /usr/lib/ranger/hadoop/etc/
sudo ln -s /usr/lib/ranger/hadoop/etc/hadoop/conf/hdfs-site.xml /usr/lib/ranger/hadoop/etc/hadoop/hdfs-site.xml || true
sudo cp -r $installpath/$ranger_hdfs_plugin/lib/* /usr/lib/hadoop-hdfs/lib/
sudo cp /usr/lib/hadoop-hdfs/lib/ranger-hdfs-plugin-impl/*.jar /usr/lib/hadoop-hdfs/lib/ || true
sudo ln -s /etc/hadoop/ /usr/lib/ranger/hadoop/

#SSL configs
sudo sed -i "s|POLICY_MGR_URL=.*|POLICY_MGR_URL=https://$ranger_fqdn:6182|g" install.properties
sudo sed -i "s|SSL_TRUSTSTORE_FILE_PATH=.*|SSL_TRUSTSTORE_FILE_PATH=${truststore_location}|g" install.properties
sudo sed -i "s|SSL_TRUSTSTORE_PASSWORD=.*|SSL_TRUSTSTORE_PASSWORD=${truststore_password}|g" install.properties
sudo sed -i "s|SSL_KEYSTORE_FILE_PATH=.*|SSL_KEYSTORE_FILE_PATH=${keystore_location}|g" install.properties
sudo sed -i "s|SSL_KEYSTORE_PASSWORD=.*|SSL_KEYSTORE_PASSWORD=${keystore_password}|g" install.properties

#Update Ranger URL in HDFS conf
sudo sed -i "s|SQL_CONNECTOR_JAR=.*|SQL_CONNECTOR_JAR=$installpath/$mysql_jar|g" install.properties
sudo sed -i "s|REPOSITORY_NAME=.*|REPOSITORY_NAME=hadoopdev|g" install.properties
sudo sed -i "s|XAAUDIT.SOLR.ENABLE=.*|XAAUDIT.SOLR.ENABLE=true|g" install.properties
sudo sed -i "s|XAAUDIT.SOLR.URL=.*|XAAUDIT.SOLR.URL=https://$ranger_fqdn:8984/solr/ranger_audits|g" install.properties
sudo sed -i "s|XAAUDIT.SOLR.SOLR_URL=.*|XAAUDIT.SOLR.SOLR_URL=https://$ranger_fqdn:8984/solr/ranger_audits|g" install.properties

#Filecache to write to local file system
sudo mkdir -p /var/log/ranger/audit/
sudo chmod -R 777 /var/log/ranger/audit/

#to solve java.lang.NoClassDefFoundError: org/apache/commons/configuration/Configuration
sed -i 's|jceks://file|localjceks://file|g' enable-hdfs-plugin.sh

#Filecache to write to local file system
if [ "$install_cloudwatch_agent_for_audit" == "true" ]; then
  sudo mkdir -p /var/log/ranger/audit/
  sudo chmod -R 777 /var/log/ranger/audit/
  sudo sed -i "s|XAAUDIT.FILECACHE.IS_ENABLED=.*|XAAUDIT.FILECACHE.IS_ENABLED=true|g" install.properties
  sudo sed -i "s|XAAUDIT.FILECACHE.FILE_SPOOL_DIR=.*|XAAUDIT.FILECACHE.FILE_SPOOL_DIR=/var/log/ranger/audit/|g" install.properties
  sudo sed -i "s|XAAUDIT.FILECACHE.FILE_SPOOL.ROLLOVER.SECS=.*|XAAUDIT.FILECACHE.FILE_SPOOL.ROLLOVER.SECS=30|g" install.properties
  sudo sed -i "s|XAAUDIT.FILECACHE.FILE_SPOOL.MAXFILES=.*|XAAUDIT.FILECACHE.FILE_SPOOL.MAXFILES=10|g" install.properties
fi

sudo -E bash enable-hdfs-plugin.sh
# new copy cammand - 01/26/2020
sudo cp -r /etc/hadoop/ranger-*.xml /etc/hadoop/conf/


#Restart Namenode
sudo puppet apply -e 'service { "hadoop-hdfs-namenode": ensure => false, }'
sudo puppet apply -e 'service { "hadoop-hdfs-namenode": ensure => true, }'
#Restart Hue
sudo sed -i '/hive.server2.logging.operation.verbose/s/kwargs/#kwargs/g' /usr/lib/hue/apps/beeswax/src/beeswax/server/hive_server2_lib.py || true
sudo puppet apply -e 'service { "hue": ensure => false, }' || true
sudo puppet apply -e 'service { "hue": ensure => true, }' || true

