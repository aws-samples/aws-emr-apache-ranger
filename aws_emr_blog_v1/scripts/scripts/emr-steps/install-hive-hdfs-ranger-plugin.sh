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
#mysql_jar_location=http://central.maven.org/maven2/mysql/mysql-connector-java/5.1.39/mysql-connector-java-5.1.39.jar
mysql_jar=mysql-connector-java-5.1.39.jar
ranger_version=$2
s3bucket=$3
ranger_download_version=0.5
if [ "$ranger_version" == "2.0" ]; then
   ranger_download_version=2.1.0-SNAPSHOT
elif [ "$ranger_version" == "1.0" ]; then
   ranger_download_version=1.1.0
elif [ "$ranger_version" == "0.7" ]; then
   ranger_download_version=0.7.1
elif [ "$ranger_version" == "0.6" ]; then
   ranger_download_version=0.6.1
else
   ranger_download_version=0.5
fi

ranger_s3bucket=$s3bucket/ranger/ranger-$ranger_download_version
ranger_hdfs_plugin=ranger-$ranger_download_version-hdfs-plugin
ranger_hive_plugin=ranger-$ranger_download_version-hive-plugin

#Setup
sudo rm -rf $installpath
sudo mkdir -p $installpath/hadoop
sudo chmod -R 777 $installpath
cd $installpath
#wget $mysql_jar_location
aws s3 cp $ranger_s3bucket/$mysql_jar . --region us-east-1
aws s3 cp $ranger_s3bucket/$ranger_hdfs_plugin.tar.gz . --region us-east-1
aws s3 cp $ranger_s3bucket/$ranger_hive_plugin.tar.gz . --region us-east-1
mkdir $ranger_hdfs_plugin
tar -xvf $ranger_hdfs_plugin.tar.gz -C $ranger_hdfs_plugin --strip-components=1
cd $installpath/$ranger_hdfs_plugin

## Scripts for old Ranger
#mkdir -p /usr/lib/ranger/hadoop/etc/hadoop/
#sudo ln -s /etc/hadoop/hdfs-site.xml /usr/lib/ranger/hadoop/etc/hadoop/hdfs-site.xml
#
#sudo ln -s /etc/hadoop/conf $installpath/hadoop/conf
#sudo ln -s /usr/lib/hadoop $installpath/hadoop/lib


## Updates for new Ranger
mkdir -p /usr/lib/ranger/hadoop/etc
sudo ln -s /etc/hadoop /usr/lib/ranger/hadoop/etc/
sudo ln -s /usr/lib/ranger/hadoop/etc/hadoop/conf/hdfs-site.xml /usr/lib/ranger/hadoop/etc/hadoop/hdfs-site.xml || true
sudo cp -r $installpath/$ranger_hdfs_plugin/lib/* /usr/lib/hadoop-hdfs/lib/
sudo cp /usr/lib/hadoop-hdfs/lib/ranger-hdfs-plugin-impl/*.jar /usr/lib/hadoop-hdfs/lib/ || true
#sudo cp /usr/lib/ranger/hadoop/etc/hadoop/conf/* /etc/hadoop/conf.empty/
#sudo cp -r /usr/lib/ranger/hadoop/etc/hadoop/conf/* /etc/hadoop/conf/
sudo ln -s /etc/hadoop/ /usr/lib/ranger/hadoop/

#Update Ranger URL in HDFS conf
sudo sed -i "s|POLICY_MGR_URL=.*|POLICY_MGR_URL=http://$ranger_fqdn:6080|g" install.properties
sudo sed -i "s|SQL_CONNECTOR_JAR=.*|SQL_CONNECTOR_JAR=$installpath/$mysql_jar|g" install.properties
sudo sed -i "s|REPOSITORY_NAME=.*|REPOSITORY_NAME=hadoopdev|g" install.properties
sudo sed -i "s|XAAUDIT.SOLR.URL=.*|XAAUDIT.SOLR.URL=http://$ranger_fqdn:8983/solr/ranger_audits|g" install.properties
sudo sed -i "s|XAAUDIT.SOLR.SOLR_URL=.*|XAAUDIT.SOLR.SOLR_URL=http://$ranger_fqdn:8983/solr/ranger_audits|g" install.properties
sudo sed -i "s|XAAUDIT.SOLR.ENABLE=.*|XAAUDIT.SOLR.ENABLE=true|g" install.properties
#sudo sed -i "s|XAAUDIT.DB.IS_ENABLED=.*|XAAUDIT.DB.IS_ENABLED=true|g" install.properties
#sudo sed -i "s|XAAUDIT.DB.HOSTNAME=.*|XAAUDIT.DB.HOSTNAME=$ranger_fqdn|g" install.properties
#sudo sed -i "s|XAAUDIT.DB.HOSTNAME=.*|XAAUDIT.DB.HOSTNAME=localhost|g" install.properties
#sudo sed -i "s|XAAUDIT.DB.DATABASE_NAME=.*|XAAUDIT.DB.DATABASE_NAME=ranger_audit|g" install.properties
#sudo sed -i "s|XAAUDIT.DB.USER_NAME=.*|XAAUDIT.DB.USER_NAME=rangerlogger|g" install.properties
#sudo sed -i "s|XAAUDIT.DB.PASSWORD=.*|XAAUDIT.DB.PASSWORD=rangerlogger|g" install.properties

sudo -E bash enable-hdfs-plugin.sh
# new copy cammand - 01/26/2020
sudo cp -r /etc/hadoop/ranger-*.xml /etc/hadoop/conf/
#Update Ranger URL in Hive Conf
mkdir -p $installpath/hive/lib
cd $installpath
mkdir $ranger_hive_plugin
tar -xvf $ranger_hive_plugin.tar.gz -C $ranger_hive_plugin --strip-components=1
cd $installpath/$ranger_hive_plugin
ln -s /etc/hive/conf $installpath/hive/conf
ln -s /usr/lib/hive $installpath/hive/lib
#export CLASSPATH=$CLASSPATH:/usr/lib/ranger/$ranger_hive_plugin/lib/ranger-*.jar
sudo -E bash -c 'echo $CLASSPATH'
sudo sed -i "s|POLICY_MGR_URL=.*|POLICY_MGR_URL=http://$ranger_fqdn:6080|g" install.properties
sudo sed -i "s|SQL_CONNECTOR_JAR=.*|SQL_CONNECTOR_JAR=/usr/lib/ranger/$mysql_jar|g" install.properties
sudo sed -i "s|REPOSITORY_NAME=.*|REPOSITORY_NAME=hivedev|g" install.properties
sudo sed -i "s|XAAUDIT.SOLR.URL=.*|XAAUDIT.SOLR.URL=http://$ranger_fqdn:8983/solr/ranger_audits|g" install.properties
sudo sed -i "s|XAAUDIT.SOLR.ENABLE=.*|XAAUDIT.SOLR.ENABLE=true|g" install.properties
#sudo sed -i "s|XAAUDIT.DB.IS_ENABLED=.*|XAAUDIT.DB.IS_ENABLED=true|g" install.properties
#sudo sed -i "s|XAAUDIT.DB.HOSTNAME=.*|XAAUDIT.DB.HOSTNAME=$ranger_fqdn|g" install.properties
#sudo sed -i "s|XAAUDIT.DB.HOSTNAME=.*|XAAUDIT.DB.HOSTNAME=localhost|g" install.properties
#sudo sed -i "s|XAAUDIT.DB.DATABASE_NAME=.*|XAAUDIT.DB.DATABASE_NAME=ranger_audit|g" install.properties
#sudo sed -i "s|XAAUDIT.DB.USER_NAME=.*|XAAUDIT.DB.USER_NAME=rangerlogger|g" install.properties
#sudo sed -i "s|XAAUDIT.DB.PASSWORD=.*|XAAUDIT.DB.PASSWORD=rangerlogger|g" install.properties
sudo -E bash enable-hive-plugin.sh
#sudo cp /usr/lib/hive/ranger-*.jar /usr/lib/hive/lib/
sudo cp $installpath/$ranger_hive_plugin/lib/ranger-hive-plugin-impl/*.jar /usr/lib/hive/
sudo cp $installpath/$ranger_hive_plugin/lib/ranger-hive-plugin-impl/*.jar /usr/lib/hive/lib/
#Restart Namenode
sudo puppet apply -e 'service { "hadoop-hdfs-namenode": ensure => false, }'
sudo puppet apply -e 'service { "hadoop-hdfs-namenode": ensure => true, }'
#Restart HiveServer2
sudo puppet apply -e 'service { "hive-server2": ensure => false, }'
sudo puppet apply -e 'service { "hive-server2": ensure => true, }'
sudo sed -i '/hive.server2.logging.operation.verbose/s/kwargs/#kwargs/g' /usr/lib/hue/apps/beeswax/src/beeswax/server/hive_server2_lib.py || true
sudo puppet apply -e 'service { "hue": ensure => false, }'
sudo puppet apply -e 'service { "hue": ensure => true, }'
