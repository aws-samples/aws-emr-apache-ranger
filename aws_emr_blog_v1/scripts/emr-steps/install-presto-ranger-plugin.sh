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
#installpath=/usr/lib/ranger
installpath=/usr/local
#mysql_jar_location=http://central.maven.org/maven2/mysql/mysql-connector-java/5.1.39/mysql-connector-java-5.1.39.jar
mysql_jar=mysql-connector-java-5.1.39.jar
s3bucket=$3
ranger_version=$2
ranger_fqdn=$1
emr_version=$4

ranger_download_version=0.5
if [ "$ranger_version" == "2.0" ]; then
   ranger_download_version=2.1.0-SNAPSHOT
elif [ "$ranger_version" == "1.0" ]; then
   ranger_download_version=1.2.1-SNAPSHOT
elif [ "$ranger_version" == "0.7" ]; then
   ranger_download_version=0.7.1
elif [ "$ranger_version" == "0.6" ]; then
   ranger_download_version=0.6.1
else
   ranger_download_version=0.5
fi

ranger_s3bucket=$s3bucket/ranger/ranger-$ranger_download_version
if [ "$emr_version" == "emr-5.30.1" ]; then
    ranger_presto_plugin=ranger-$ranger_download_version-prestodb-plugin-presto232
  else
    ranger_presto_plugin=ranger-$ranger_download_version-prestodb-plugin
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
sudo sed -i "s|POLICY_MGR_URL=.*|POLICY_MGR_URL=http://$ranger_fqdn:6080|g" install.properties
sudo sed -i "s|SQL_CONNECTOR_JAR=.*|SQL_CONNECTOR_JAR=/usr/lib/ranger/$mysql_jar|g" install.properties
sudo sed -i "s|REPOSITORY_NAME=.*|REPOSITORY_NAME=prestodev|g" install.properties
sudo sed -i "s|XAAUDIT.SOLR.URL=.*|XAAUDIT.SOLR.URL=http://$ranger_fqdn:8983/solr/ranger_audits|g" install.properties
sudo sed -i "s|XAAUDIT.SOLR.SOLR_URL=.*|XAAUDIT.SOLR.SOLR_URL=http://$ranger_fqdn:8983/solr/ranger_audits|g" install.properties
sudo sed -i "s|XAAUDIT.SOLR.ENABLE=.*|XAAUDIT.SOLR.ENABLE=true|g" install.properties
sudo sed -i "s|XAAUDIT.SOLR.IS_ENABLED=.*|XAAUDIT.SOLR.IS_ENABLED=true|g" install.properties
echo "XAAUDIT.SUMMARY.ENABLE=true" | sudo tee -a install.properties
#sudo sed -i "s|XAAUDIT.DB.HOSTNAME=.*|XAAUDIT.DB.HOSTNAME=localhost|g" install.properties
#sudo sed -i "s|XAAUDIT.DB.DATABASE_NAME=.*|XAAUDIT.DB.DATABASE_NAME=ranger_audit|g" install.properties
#sudo sed -i "s|XAAUDIT.DB.USER_NAME=.*|XAAUDIT.DB.USER_NAME=rangerlogger|g" install.properties
#sudo sed -i "s|XAAUDIT.DB.PASSWORD=.*|XAAUDIT.DB.PASSWORD=rangerlogger|g" install.properties
#sudo sed -i "s|XAAUDIT.DB.IS_ENABLED=.*|XAAUDIT.DB.IS_ENABLED=true|g" install.properties
#sudo sed -i "s|XAAUDIT.DB.HOSTNAME=.*|XAAUDIT.DB.HOSTNAME=$ranger_fqdn|g" install.properties
sudo mkdir -p /usr/presto/etc/
sudo ln -s /etc/presto/conf/ /usr/presto/conf/ || true
sudo ln -s /usr/lib/presto/ /usr/presto/ || true
sudo -E bash enable-prestodb-plugin.sh

sudo cp /usr/presto/etc/access-control.properties /usr/lib/presto/etc/
sudo cp -r /usr/presto/plugin/ranger /usr/lib/presto/plugin/

sudo cp /usr/lib/presto/lib/javax.ws*.jar /usr/lib/presto/plugin/ranger/
sudo cp /usr/share/java/javamail.jar /usr/lib/presto/plugin/ranger/ || true
sudo aws s3 cp $ranger_s3bucket/jdom-1.1.3.jar /usr/lib/presto/plugin/ranger/ --region us-east-1
sudo aws s3 cp $ranger_s3bucket/rome-0.9.jar /usr/lib/presto/plugin/ranger/ --region us-east-1
sudo aws s3 cp $ranger_s3bucket/javax.mail-api-1.6.0.jar /usr/lib/presto/plugin/ranger/ --region us-east-1

sudo ln -s /usr/lib/presto/plugin/ranger/ranger-prestodb-plugin-impl/conf /usr/lib/presto/plugin/ranger/ || true

## Added for hive integration
sudo sed -i "s|ranger_host|$ranger_fqdn|g" /usr/lib/presto/plugin/ranger/conf/ranger-hive-*.xml
#sudo ln -s /etc/hive/conf.dist/ranger-hive-security.xml /usr/lib/presto/plugin/ranger/conf/ranger-hive-security.xml || true
#sudo ln -s /etc/hive/conf.dist/ranger-hive-audit.xml /usr/lib/presto/plugin/ranger/conf/ranger-hive-audit.xml || true

sudo puppet apply -e 'service { "presto-server": ensure => false, }'
sudo puppet apply -e 'service { "presto-server": ensure => true, }'

sudo sed -i "s|PrestoDriver\", \"user\":\"root\",\"password\":\"\"|PrestoDriver\", \"user\":\"\", \"password\":\"\"|g" /etc/hue/conf.empty/hue.ini
sudo puppet apply -e 'service { "hue": ensure => false, }'
sudo puppet apply -e 'service { "hue": ensure => true, }'
