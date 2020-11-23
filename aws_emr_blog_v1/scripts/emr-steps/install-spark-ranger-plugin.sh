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

#s3bucket={{ssm:s3scriptpath}}
#ranger_version={{ssm:rangerversion}}
#ranger_fqdn={{ssm:rangerhostname}}

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
ranger_spark_plugin=ranger-$ranger_download_version-plugin-spark

#Setup
sudo rm -rf /usr/local/ranger*
sudo rm -rf /usr/presto/*
sudo rm -rf /usr/lib/presto/plugin/ranger/*.jar
sudo rm -rf $installpath/$ranger_spark_plugin
sudo mkdir -p $installpath
sudo chmod -R 777 $installpath
cd $installpath
#wget $mysql_jar_location
aws s3 cp $ranger_s3bucket/$ranger_spark_plugin.tar.gz . --region us-east-1

#cd $installpath
SPARK_HOME=/usr/lib/spark
sudo mkdir $ranger_spark_plugin
sudo tar -xvf $ranger_spark_plugin.tar.gz -C $ranger_spark_plugin --strip-components=1

cd $installpath/$ranger_spark_plugin

sudo sed -i "s|ranger_host|$ranger_fqdn|g" install/conf/ranger-*.xml
#sudo sed -i "s|ranger_host|$ranger_fqdn|g" install/conf/ranger-hive-security.xml

sudo cp lib/* $SPARK_HOME/jars/
#sudo cp install/lib/* $SPARK_HOME/jars/
sudo cp install/conf/* $SPARK_HOME/conf/ || true

sudo chmod 777 -R /etc/spark/conf/ranger-*
sudo puppet apply -e 'service { "spark-thriftserver": ensure => false, }' || true
sudo puppet apply -e 'service { "spark-thriftserver": ensure => true, }' || true

sudo puppet apply -e 'service { "hue": ensure => false, }' || true
sudo puppet apply -e 'service { "hue": ensure => true, }' || true
