#!/bin/bash
set -euo pipefail
set -x
#Variables
if [[ -n "$JAVA_HOME" ]] && [[ -x "$JAVA_HOME/bin/java" ]]; then
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
installpath=/usr/lib/ranger
ranger_server_fqdn=$1
#mysql_jar_location=http://central.maven.org/maven2/mysql/mysql-connector-java/5.1.39/mysql-connector-java-5.1.39.jar
mysql_jar=mysql-connector-java-5.1.39.jar
default_region=${2-'us-east-1'}
ranger_version=${3-'2.0'}
s3bucket=${4-'aws-bigdata-blog'}
s3bucketKey=${5-'artifacts/aws-blog-emr-ranger'}
project_version=${6-'3.0'}
emr_version=${7-'emr-5.30'}
http_protocol=${8-'https'}
install_cloudwatch_agent_for_audit=${9-'false'}

if [ "$http_protocol" == "https" ]; then
  RANGER_HTTP_URL=https://$ranger_server_fqdn:6182
  SOLR_HTTP_URL=https://$ranger_server_fqdn:8984
else
  RANGER_HTTP_URL=http://$ranger_server_fqdn:6080
  SOLR_HTTP_URL=http://$ranger_server_fqdn:8983
fi

ranger_download_version=0.5

emr_release_version_regex="^emr-6.*"
if [[ ("$emr_version" =~ $emr_release_version_regex) && ("$ranger_version" == "2.0") ]]; then
  ranger_download_version=2.2.0-SNAPSHOT
elif [ "$ranger_version" == "2.0" ]; then
  ranger_download_version=2.1.0-SNAPSHOT
else
  ranger_download_version=1.1.0
fi

ranger_s3bucket=s3://${s3bucket}/${s3bucketKey}/ranger/ranger-$ranger_download_version
ranger_hdfs_plugin=ranger-$ranger_download_version-hdfs-plugin

## --- SSL Config ---

## Cert configuration
certs_s3_location=s3://${s3bucket}/${s3bucketKey}/${project_version}/emr-tls/
certs_path="/tmp/certs"

ranger_agents_certs_path="${certs_path}/ranger-agents-certs"
ranger_server_certs_path="${certs_path}/ranger-server-certs"

truststore_ranger_server_alias="rangerServerTrust"
keystore_alias="rangerAgent"
truststore_password="changeit"
keystore_password="changeit"
truststore_location="/etc/hadoop/conf/ranger-plugin-truststore.jks"
keystore_location="/etc/hadoop/conf/ranger-plugin-keystore.jks"

mkdir -p ${ranger_agents_certs_path}
mkdir -p ${ranger_server_certs_path}

sudo yum -y install https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm || true
sudo yum install jq -y
# setup ranger plugin keystore and trust store
aws secretsmanager get-secret-value --secret-id emr/rangerPluginCert --version-stage AWSCURRENT --region $default_region | jq -r ".SecretString" >${ranger_agents_certs_path}/certificateChain.pem
aws secretsmanager get-secret-value --secret-id emr/rangerGAagentkey --version-stage AWSCURRENT --region $default_region | jq -r ".SecretString" >${ranger_agents_certs_path}/privateKey.pem

openssl pkcs12 -export -in ${ranger_agents_certs_path}/certificateChain.pem -inkey ${ranger_agents_certs_path}/privateKey.pem -chain -CAfile ${ranger_agents_certs_path}/certificateChain.pem -name ${keystore_alias} -out ${ranger_agents_certs_path}/keystore.p12 -password pass:${keystore_password}
keytool -delete -alias ${keystore_alias} -keystore ${keystore_location} -storepass ${keystore_password} -noprompt || true
sudo keytool -importkeystore -deststorepass ${keystore_password} -destkeystore ${keystore_location} -srckeystore ${ranger_agents_certs_path}/keystore.p12 -srcstoretype PKCS12 -srcstorepass ${keystore_password}
sudo chmod 444 ${keystore_location}
# -----

# setup ranger admin server trust store
aws secretsmanager get-secret-value --secret-id emr/rangerGAservercert --version-stage AWSCURRENT --region $default_region | jq -r ".SecretString" > ${ranger_server_certs_path}/trustedCertificates.pem

sudo keytool -delete -alias ${truststore_ranger_server_alias} -keystore ${truststore_location} -storepass ${truststore_password} -noprompt || true
sudo keytool -import -file ${ranger_server_certs_path}/trustedCertificates.pem -alias ${truststore_ranger_server_alias} -keystore ${truststore_location} -storepass ${truststore_password} -noprompt
# -----

#Setup
sudo rm -rf $installpath/*hdfs*
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

## Copy the keystore and strustone information
sudo cp /etc/hive/conf/ranger-plugin-keystore.jks /etc/hadoop/conf/
sudo cp /etc/hive/conf/ranger-keystore-creds.jceks /etc/hadoop/conf/
sudo cp /etc/hive/conf/ranger-plugin-truststore.jks /etc/hadoop/conf/
sudo cp /etc/hive/conf/ranger-truststore-creds.jceks /etc/hadoop/conf/
#SSL configs
sudo sed -i "s|POLICY_MGR_URL=.*|POLICY_MGR_URL=$RANGER_HTTP_URL|g" install.properties
sudo sed -i "s|SSL_TRUSTSTORE_FILE_PATH=.*|SSL_TRUSTSTORE_FILE_PATH=${truststore_location}|g" install.properties
sudo sed -i "s|SSL_TRUSTSTORE_PASSWORD=.*|SSL_TRUSTSTORE_PASSWORD=${truststore_password}|g" install.properties
sudo sed -i "s|SSL_KEYSTORE_FILE_PATH=.*|SSL_KEYSTORE_FILE_PATH=${keystore_location}|g" install.properties
sudo sed -i "s|SSL_KEYSTORE_PASSWORD=.*|SSL_KEYSTORE_PASSWORD=${keystore_password}|g" install.properties

#Update Ranger URL in HDFS conf
sudo sed -i "s|SQL_CONNECTOR_JAR=.*|SQL_CONNECTOR_JAR=$installpath/$mysql_jar|g" install.properties
sudo sed -i "s|REPOSITORY_NAME=.*|REPOSITORY_NAME=hadoopdev|g" install.properties
sudo sed -i "s|XAAUDIT.SOLR.ENABLE=.*|XAAUDIT.SOLR.ENABLE=true|g" install.properties
sudo sed -i "s|XAAUDIT.SOLR.URL=.*|XAAUDIT.SOLR.URL=$SOLR_HTTP_URL/solr/ranger_audits|g" install.properties
sudo sed -i "s|XAAUDIT.SOLR.SOLR_URL=.*|XAAUDIT.SOLR.SOLR_URL=$SOLR_HTTP_URL/solr/ranger_audits|g" install.properties

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

#---- Restart Namenode
sudo ${puppet_cmd} apply -e 'service { "hadoop-hdfs-namenode": ensure => false, }'
sudo ${puppet_cmd} apply -e 'service { "hadoop-hdfs-namenode": ensure => true, }'
