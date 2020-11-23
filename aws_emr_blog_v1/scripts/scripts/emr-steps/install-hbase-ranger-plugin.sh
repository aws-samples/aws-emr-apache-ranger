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
ranger_fqdn=$1
mysql_jar_location=http://central.maven.org/maven2/mysql/mysql-connector-java/5.1.39/mysql-connector-java-5.1.39.jar
mysql_jar=mysql-connector-java-5.1.39.jar
ranger_version=$2
s3bucket=$3
if [ "$ranger_version" == "1.0" ]; then
   ranger_s3bucket=$s3bucket/ranger/ranger-1.1.0
   ranger_hdfs_plugin=ranger-1.1.0-hbase-plugin
   ranger_hive_plugin=ranger-1.1.0-hbase-plugin
elif [ "$ranger_version" == "0.7" ]; then
   ranger_s3bucket=$s3bucket/ranger/ranger-0.7.1
   ranger_hbase_plugin=ranger-0.7.1-hbase-plugin
elif [ "$ranger_version" == "0.6" ]; then
   ranger_s3bucket=$s3bucket/ranger/ranger-0.6.1
   ranger_hbase_plugin=ranger-0.6.1-hbase-plugin
else
   ranger_s3bucket=$s3bucket/ranger/ranger-0.5
   ranger_hbase_plugin=ranger-0.5.3-hbase-plugin
fi
#Setup
sudo rm -rf $installpath
sudo mkdir -p $installpath/hbase
sudo chmod -R 777 $installpath
cd $installpath
wget $mysql_jar_location
aws s3 cp $ranger_s3bucket/$ranger_hbase_plugin.tar.gz . --region us-east-1
tar -xvf $ranger_hbase_plugin.tar.gz
cd $installpath/$ranger_hbase_plugin
ln -s /etc/hbase/conf $installpath/hbase/conf || true
ln -s /usr/lib/hbase $installpath/hbase/lib || true
#Update Ranger URL in HBASE conf
sudo sed -i "s|POLICY_MGR_URL=.*|POLICY_MGR_URL=http://$ranger_fqdn:6080|g" install.properties
sudo sed -i "s|XAAUDIT.DB.HOSTNAME=.*|XAAUDIT.DB.HOSTNAME=localhost|g" install.properties
sudo sed -i "s|XAAUDIT.DB.DATABASE_NAME=.*|XAAUDIT.DB.DATABASE_NAME=ranger_audit|g" install.properties
sudo sed -i "s|XAAUDIT.DB.USER_NAME=.*|XAAUDIT.DB.USER_NAME=rangerlogger|g" install.properties
sudo sed -i "s|XAAUDIT.DB.PASSWORD=.*|XAAUDIT.DB.PASSWORD=rangerlogger|g" install.properties
sudo sed -i "s|SQL_CONNECTOR_JAR=.*|SQL_CONNECTOR_JAR=$installpath/$mysql_jar|g" install.properties
sudo sed -i "s|REPOSITORY_NAME=.*|REPOSITORY_NAME=hbasedev|g" install.properties
sudo sed -i "s|XAAUDIT.SOLR.URL=.*|XAAUDIT.SOLR.URL=http://$ranger_fqdn:8983/solr/ranger_audits|g" install.properties
sudo sed -i "s|XAAUDIT.SOLR.SOLR_URL=.*|XAAUDIT.SOLR.SOLR_URL=http://$ranger_fqdn:8983/solr/ranger_audits|g" install.properties
sudo sed -i "s|XAAUDIT.SOLR.ENABLE=.*|XAAUDIT.SOLR.ENABLE=true|g" install.properties
sudo sed -i "s|XAAUDIT.DB.IS_ENABLED=.*|XAAUDIT.DB.IS_ENABLED=true|g" install.properties
sudo sed -i "s|XAAUDIT.DB.HOSTNAME=.*|XAAUDIT.DB.HOSTNAME=$ranger_fqdn|g" install.properties
sudo -E bash enable-hbase-plugin.sh
#Restart HBase service
sudo puppet apply -e 'service { "hbase-master": ensure => false, }' || true
sudo puppet apply -e 'service { "hbase-master": ensure => true, }' || true
sudo puppet apply -e 'service { "hbase-regionserver": ensure => false, }' || true
sudo puppet apply -e 'service { "hbase-regionserver": ensure => true, }' || true
