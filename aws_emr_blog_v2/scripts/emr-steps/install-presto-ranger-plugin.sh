#!/bin/bash
set -euo pipefail
set -x
#Variables
if [[ -n "$JAVA_HOME" ]] && [[ -x "$JAVA_HOME/bin/java" ]];  then
  echo "found java executable in JAVA_HOME"
else
  export JAVA_HOME=/usr/lib/jvm/java-openjdk
fi
if [ -f "/opt/aws/puppet/bin/puppet" ]; then
  echo "Puppet found in path"
  puppet_cmd='/opt/aws/puppet/bin/puppet'
else
  puppet_cmd='puppet'
fi
sudo -E bash -c 'echo $JAVA_HOME'
#installpath=/usr/lib/ranger
#installpath=/usr/lib/ranger
installpath=/usr/local
#mysql_jar_location=http://central.maven.org/maven2/mysql/mysql-connector-java/5.1.39/mysql-connector-java-5.1.39.jar
mysql_jar=mysql-connector-java-5.1.39.jar
s3bucket=$3
project_version=${4-'2.0'}
ranger_version=$2
ranger_server_fqdn=$1
emr_version=$5
presto_engine=$6
http_protocol=${7-'http'}
install_cloudwatch_agent_for_audit=${8-'false'}

if [ "$http_protocol" == "https" ]; then
  RANGER_HTTP_URL=https://$ranger_server_fqdn:6182
  SOLR_HTTP_URL=https://$ranger_server_fqdn:8984
else
  RANGER_HTTP_URL=http://$ranger_server_fqdn:6080
  SOLR_HTTP_URL=http://$ranger_server_fqdn:8983
fi

ranger_download_version=0.5
if [[ ("$ranger_version" == "2.0" || "$ranger_version" == "2.2") ]]; then
  if [ "$presto_engine" == "PrestoSQL" ]; then
    ranger_download_version=2.2.0-SNAPSHOT
  else
    ranger_download_version=2.1.0-SNAPSHOT
  fi
elif [ "$ranger_version" == "1.0" ]; then
   ranger_download_version=1.2.1-SNAPSHOT
elif [ "$ranger_version" == "0.7" ]; then
   ranger_download_version=0.7.1
elif [ "$ranger_version" == "0.6" ]; then
   ranger_download_version=0.6.1
else
   ranger_download_version=0.5
fi

engine_name=prestodb
emr_release_version_regex="^(emr-5.30*|emr-6.*)"
if [[ "$emr_version" =~ $emr_release_version_regex ]]; then
    ranger_presto_plugin=ranger-$ranger_download_version-prestodb-plugin-presto232
  else
    ranger_presto_plugin=ranger-$ranger_download_version-prestodb-plugin
fi

emr_release_version_regex="^(emr-6.1*)"
if [[ ("$emr_version" =~ $emr_release_version_regex && "$presto_engine" == "PrestoSQL") ]]; then
  ranger_presto_plugin=ranger-$ranger_download_version-presto-plugin
  engine_name=presto
fi

ranger_s3bucket=$s3bucket/ranger/ranger-$ranger_download_version

## --- SSL Config ---

## Cert configuration
certs_s3_location=${s3bucket}/${project_version}/emr-tls/
certs_path="/tmp/certs"

ranger_agents_certs_path="${certs_path}/ranger-agents-certs"
ranger_server_certs_path="${certs_path}/ranger-server-certs"
solr_certs_path="${certs_path}/solr-client-certs"

truststore_ranger_server_alias="rangerServerTrust"
truststore_solr_alias="solrtrust"
truststore_password="changeit"
truststore_location="/etc/hadoop/conf/ranger-plugin-truststore.jks"
jvm_truststore_location="$JAVA_HOME/lib/security/cacerts"

keystore_alias="rangerAgent"
keystore_password="changeit"
keystore_location="/etc/hadoop/conf/ranger-plugin-keystore.jks"

if [ ! -f "$truststore_location" ] || [ ! -f "$keystore_location" ]; then
  echo "$truststore_location does not exist. will download the create"
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
  sudo keytool -delete -alias ${truststore_solr_alias} -keystore ${jvm_truststore_location} -storepass ${truststore_password} -noprompt || true
  sudo keytool -import -file ${solr_certs_path}/trustedCertificates.pem -alias ${truststore_solr_alias} -keystore ${jvm_truststore_location} -storepass ${truststore_password} -noprompt

  #cleanup
  rm -rf ${certs_path}
fi

#Setup
sudo rm -rf $installpath/$ranger_presto_plugin
sudo rm -rf /usr/presto/*
sudo rm -rf /usr/lib/presto/plugin/ranger
sudo mkdir -p $installpath
sudo chmod -R 777 $installpath
cd $installpath
aws s3 cp $ranger_s3bucket/$ranger_presto_plugin.tar.gz . --region us-east-1

#cd $installpath
sudo mkdir $ranger_presto_plugin
sudo tar -xvf $ranger_presto_plugin.tar.gz -C $ranger_presto_plugin --strip-components=1

cd $installpath/$ranger_presto_plugin
#export CLASSPATH=$CLASSPATH:/usr/lib/ranger/$ranger_presto_plugin/lib/ranger-*.jar
sudo -E bash -c 'echo $CLASSPATH'
#SSL configs
sudo sed -i "s|POLICY_MGR_URL=.*|POLICY_MGR_URL=$RANGER_HTTP_URL|g" install.properties
sudo sed -i "s|SSL_TRUSTSTORE_FILE_PATH=.*|SSL_TRUSTSTORE_FILE_PATH=${truststore_location}|g" install.properties
sudo sed -i "s|SSL_TRUSTSTORE_PASSWORD=.*|SSL_TRUSTSTORE_PASSWORD=${truststore_password}|g" install.properties
sudo sed -i "s|SSL_KEYSTORE_FILE_PATH=.*|SSL_KEYSTORE_FILE_PATH=${keystore_location}|g" install.properties
sudo sed -i "s|SSL_KEYSTORE_PASSWORD=.*|SSL_KEYSTORE_PASSWORD=${keystore_password}|g" install.properties

sudo sed -i "s|SQL_CONNECTOR_JAR=.*|SQL_CONNECTOR_JAR=/usr/lib/ranger/$mysql_jar|g" install.properties
sudo sed -i "s|REPOSITORY_NAME=.*|REPOSITORY_NAME=prestodev|g" install.properties
sudo sed -i "s|XAAUDIT.SOLR.URL=.*|XAAUDIT.SOLR.URL=$SOLR_HTTP_URL/solr/ranger_audits|g" install.properties
sudo sed -i "s|XAAUDIT.SOLR.SOLR_URL=.*|XAAUDIT.SOLR.SOLR_URL=$SOLR_HTTP_URL/solr/ranger_audits|g" install.properties
sudo sed -i "s|XAAUDIT.SOLR.ENABLE=.*|XAAUDIT.SOLR.ENABLE=true|g" install.properties
sudo sed -i "s|XAAUDIT.SOLR.IS_ENABLED=.*|XAAUDIT.SOLR.IS_ENABLED=true|g" install.properties
echo "XAAUDIT.SUMMARY.ENABLE=true" | sudo tee -a install.properties

## HDFS Audit
#current_hostname=$(hostname -f)
#presto_log_dir=/tmp/ranger
#
#sudo sed -i "s|XAAUDIT.HDFS.ENABLE=.*|XAAUDIT.HDFS.ENABLE=true|g" install.properties
#sudo sed -i "s|XAAUDIT.HDFS.HDFS_DIR=.*|XAAUDIT.HDFS.HDFS_DIR=hdfs://$current_hostname:8020/ranger/audit|g" install.properties
#sudo sed -i "s|XAAUDIT.HDFS.FILE_SPOOL_DIR=.*|XAAUDIT.HDFS.FILE_SPOOL_DIR=$presto_log_dir/audit/hdfs/spool|g" install.properties
#sudo sed -i "s|XAAUDIT.HDFS.IS_ENABLED=.*|XAAUDIT.HDFS.IS_ENABLED=true|g" install.properties
#sudo sed -i "s|XAAUDIT.HDFS.DESTINATION_DIRECTORY=.*|XAAUDIT.HDFS.DESTINATION_DIRECTORY=hdfs://$current_hostname:8020/ranger/audit/%app-type%/%time:yyyyMMdd%|g" install.properties
#sudo sed -i "s|XAAUDIT.HDFS.LOCAL_BUFFER_DIRECTORY=.*|XAAUDIT.HDFS.LOCAL_BUFFER_DIRECTORY=$presto_log_dir/audit/%app-type%|g" install.properties
#sudo sed -i "s|XAAUDIT.HDFS.LOCAL_ARCHIVE_DIRECTORY=.*|XAAUDIT.HDFS.LOCAL_ARCHIVE_DIRECTORY=$presto_log_dir/audit/archive/%app-type%|g" install.properties
#echo "XAAUDIT.SUMMARY.ENABLE=true" | sudo tee -a install.properties
#sudo cp /usr/lib/hadoop-hdfs/hadoop-* /usr/lib/presto/plugin/ranger/ranger-$engine_name-plugin-impl/

if [ "$install_cloudwatch_agent_for_audit" == "true" ]; then
  #Filecache to write to local file system
  sudo mkdir -p /var/log/ranger/audit/
  sudo chmod -R 777 /var/log/ranger/audit/
  sudo sed -i "s|XAAUDIT.FILECACHE.IS_ENABLED=.*|XAAUDIT.FILECACHE.IS_ENABLED=true|g" install.properties
  sudo sed -i "s|XAAUDIT.FILECACHE.FILE_SPOOL_DIR=.*|XAAUDIT.FILECACHE.FILE_SPOOL_DIR=/var/log/ranger/audit/|g" install.properties
  sudo sed -i "s|XAAUDIT.FILECACHE.FILE_SPOOL.ROLLOVER.SECS=.*|XAAUDIT.FILECACHE.FILE_SPOOL.ROLLOVER.SECS=30|g" install.properties
  sudo sed -i "s|XAAUDIT.FILECACHE.FILE_SPOOL.MAXFILES=.*|XAAUDIT.FILECACHE.FILE_SPOOL.MAXFILES=10|g" install.properties
fi


sudo mkdir -p /usr/presto/etc/
sudo ln -sfn /etc/presto/conf/ /usr/presto/conf/ || true
sudo ln -sfn /usr/lib/presto/ /usr/presto/ || true

sudo sed -i 's|jceks://file|localjceks://file|g' enable-$engine_name-plugin.sh
sudo ln -sfn /etc/hadoop/conf/core-site.xml /etc/presto/conf/
sudo ln -sfn /etc/hadoop/conf/hdfs-site.xml /etc/presto/conf/

sudo -E bash enable-$engine_name-plugin.sh

sudo cp /usr/presto/etc/access-control.properties /usr/lib/presto/etc/ || true
sudo cp -r /usr/presto/plugin/ranger /usr/lib/presto/plugin/

sudo cp /usr/lib/presto/lib/javax.ws*.jar /usr/lib/presto/plugin/ranger/
sudo cp /usr/share/java/javamail.jar /usr/lib/presto/plugin/ranger/ || true
sudo aws s3 cp $ranger_s3bucket/jdom-1.1.3.jar /usr/lib/presto/plugin/ranger/ --region us-east-1
sudo aws s3 cp $ranger_s3bucket/rome-0.9.jar /usr/lib/presto/plugin/ranger/ --region us-east-1
sudo aws s3 cp $ranger_s3bucket/javax.mail-api-1.6.0.jar /usr/lib/presto/plugin/ranger/ --region us-east-1

sudo ln -sfn /usr/lib/presto/plugin/ranger/ranger-$engine_name-plugin-impl/conf /usr/lib/presto/plugin/ranger/ || true
sudo ln -sfn /etc/hadoop/conf/core-site.xml /usr/lib/presto/plugin/ranger/ || true
sudo ln -sfn /etc/hadoop/conf/hdfs-site.xml /usr/lib/presto/plugin/ranger/ || true

## Added for hive integration
sudo sed -i "s|ranger_host|$ranger_server_fqdn|g" /usr/lib/presto/plugin/ranger/conf/ranger-hive-*.xml || true
#sudo ln -sfn /etc/hive/conf.dist/ranger-hive-security.xml /usr/lib/presto/plugin/ranger/conf/ranger-hive-security.xml || true
#sudo ln -sfn /etc/hive/conf.dist/ranger-hive-audit.xml /usr/lib/presto/plugin/ranger/conf/ranger-hive-audit.xml || true

sudo ${puppet_cmd} apply -e 'service { "presto-server": ensure => false, }'
sudo ${puppet_cmd} apply -e 'service { "presto-server": ensure => true, }'

sudo sed -i "s|PrestoDriver\", \"user\":\"root\",\"password\":\"\"|PrestoDriver\", \"user\":\"\", \"password\":\"\"|g" /etc/hue/conf.empty/hue.ini
sudo ${puppet_cmd} apply -e 'service { "hue": ensure => false, }'
sudo ${puppet_cmd} apply -e 'service { "hue": ensure => true, }'
