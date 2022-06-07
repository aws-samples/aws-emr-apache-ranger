#!/bin/bash
#===============================================================================
#!# script: install-ranger-admin-server.sh
#!# authors: Varun Bhamidimarri, Stefano Sandonà, Lorenzo Ripani
#!# version: v2.0
#!# license: MIT license
#!#
#!# Script to setup the Apache Ranger Server
#===============================================================================
#?#
#?# usage: ./install-ranger-admin-server.sh <ldap_ip_address> <ldap_base_dn> <ldap_bind_user_dn> <ldap_bind_password> <ranger_version> <s3bucket> <project_version> <database_host> <database_admin_password>
#?#        ./install-ranger-admin-server.sh <ldap_ip_address> dc=awsemr,dc=com binduser@awsemr.com <ldap_bind_password> 2.0 s3://aws-bigdata-blog/artifacts/aws-blog-emr-ranger 3.0 <rds-database-name>.rds.amazonaws.com <RANGER_DB_ADMIN_PASSWORD>
#?#
#?#   ldap_ip_address                 ip address or hostname of the LDAP server
#?#   ldap_base_dn                    LDAP base DN. eg. dc=awsemr,dc=com
#?#   ldap_bind_user_dn               LDAP bind username  eg. binduser@awsemr.com
#?#   ldap_bind_password              LDAP bind user password
#?#   ranger_version                  Ranger version installed. This parameter corresponds to the build located on the S3 bucket
#?#   s3bucket                        S3 bucket location where the artificats are stored
#?#   project_version                 Project version of the cloud formation template used
#?#   database_host                   Database hostname where the Ranger Schema will be created
#?#   database_admin_password         Database admin password for the `root` user.
#?#
#===============================================================================

set -euo pipefail
set -x

# Force the script to run as root
if [ $(id -u) != "0" ]
then
    sudo "$0" "$@"
    exit $?
fi

# Print the usage helper using the header as source
function usage() {
  [ "$*" ] && echo "$0: $*"
  sed -n '/^#?#/,/^$/s/^#?# \{0,1\}//p' "$0"
  exit -1
}

[[ $# -lt 9  ]] && echo "error: wrong parameters" && usage

yum -y install java-1.8.0
yum -y remove java-1.7.0-openjdk
yum -y install krb5-workstation krb5-libs krb5-auth-dialog

export JAVA_HOME=/usr/lib/jvm/jre

# Define variables
hostname=`hostname -I | xargs`
installpath=/usr/lib/ranger

ldap_ip_address=$1
ldap_base_dn=$2
ldap_bind_user_dn=$3
ldap_bind_password=$4
ranger_version=$5
s3bucket=$6
project_version=${7-'2.0'}
RANGER_DB_HOST=$8
RANGER_DB_ADMIN_PASSWORD=$9
default_region=${10-'us-east-1'}
ldap_server_url=ldap://$ldap_ip_address
ranger_service_def_ver=2.0.0


if [ "$ranger_version" == "2.0" ]; then
   ranger_download_version=2.1.0-SNAPSHOT
   ranger_service_def_ver=2.0.0
else
   ranger_download_version=1.0.1
fi

ranger_s3bucket=$s3bucket/ranger/ranger-$ranger_download_version
ranger_admin_server=ranger-$ranger_download_version-admin
ranger_user_sync=ranger-$ranger_download_version-usersync

# mysql
mysql_version="8.0.26"
mysql_jar="mysql-connector-java-$mysql_version.jar"
mysql_jar_location="https://repo1.maven.org/maven2/mysql/mysql-connector-java/$mysql_version/mysql-connector-java-$mysql_version.jar"

certs_path="/tmp/certs"

current_hostname=$(TOKEN=`curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600"` && curl -H "X-aws-ec2-metadata-token: $TOKEN" -v http://169.254.169.254/latest/meta-data/local-hostname)
hostname $current_hostname

HTTP_URL=https://localhost:6182
ranger_agents_certs_path="${certs_path}/ranger-agents-certs"
ranger_server_certs_path="${certs_path}/ranger-server-certs"
solr_certs_path="${certs_path}/solr-client-certs"

ranger_admin_keystore_alias="rangeradmin"
ranger_admin_keystore_password="changeit"
ranger_admin_keystore_location="/etc/ranger/admin/conf/ranger-admin-keystore.jks"
ranger_admin_truststore_location="$JAVA_HOME/lib/security/cacerts"
ranger_admin_truststore_password="changeit"


solr_keystore_location="/etc/solr/conf/solr.jks"
solr_keystore_alias="solr"
solr_keystore_password="changeit"

truststore_plugins_alias="rangerplugin"
truststore_solr_alias="solrTrust"
truststore_admin_alias="rangeradmin"


RANGER_DB_ADMIN="root"
RANGER_DB_SCHEMA="rangerdb"
RANGER_DB_USER="rangeradmin"
RANGER_DB_USER_PASSWORD="rangeradmin"

#===============================================================================
# Certificates setup
#===============================================================================
rm -rf ${certs_path}
mkdir -p ${certs_path}

mkdir -p ${ranger_agents_certs_path}
mkdir -p ${ranger_server_certs_path}
mkdir -p ${solr_certs_path}

# Using Secrets Manager to get the private Key and certs
yum -y install https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm || true
yum install jq -y
aws secretsmanager get-secret-value --secret-id emr/rangerServerPrivateKey --version-stage AWSCURRENT --region $default_region | jq -r ".SecretString"  > ${ranger_server_certs_path}/privateKey.pem
aws secretsmanager get-secret-value --secret-id emr/rangerGAservercert --version-stage AWSCURRENT --region $default_region | jq -r ".SecretString"  > ${ranger_server_certs_path}/trustedCertificates.pem
aws secretsmanager get-secret-value --secret-id emr/rangerPluginCert --version-stage AWSCURRENT --region $default_region | jq -r ".SecretString"  > ${ranger_agents_certs_path}/trustedCertificates.pem
aws secretsmanager get-secret-value --secret-id emr/rangerSolrCert --version-stage AWSCURRENT --region $default_region | jq -r ".SecretString"  > ${solr_certs_path}/certificateChain.pem
aws secretsmanager get-secret-value --secret-id emr/rangerSolrPrivateKey --version-stage AWSCURRENT --region $default_region | jq -r ".SecretString"  > ${solr_certs_path}/privateKey.pem
aws secretsmanager get-secret-value --secret-id emr/rangerSolrTrustedCert --version-stage AWSCURRENT --region $default_region | jq -r ".SecretString"  > ${solr_certs_path}/trustedCertificates.pem

mkdir -p /etc/ranger/admin/conf

# Setup Keystore for RangerAdmin
openssl pkcs12 -export -in ${ranger_server_certs_path}/trustedCertificates.pem -inkey ${ranger_server_certs_path}/privateKey.pem -chain -CAfile ${ranger_server_certs_path}/trustedCertificates.pem -name ${ranger_admin_keystore_alias} -out ${ranger_server_certs_path}/keystore.p12 -password pass:${ranger_admin_keystore_password}
keytool -delete -alias ${ranger_admin_keystore_alias} -keystore ${ranger_admin_keystore_location} -storepass ${ranger_admin_keystore_password} -noprompt || true
keytool -importkeystore -deststorepass ${ranger_admin_keystore_password} -destkeystore ${ranger_admin_keystore_location} -srckeystore ${ranger_server_certs_path}/keystore.p12 -srcstoretype PKCS12 -srcstorepass ${ranger_admin_keystore_password}

# Setup Truststore - add agent cert to Ranger Admin
keytool -delete -alias ${truststore_plugins_alias} -keystore ${ranger_admin_truststore_location} -storepass changeit -noprompt || true
keytool -import -file ${ranger_agents_certs_path}/trustedCertificates.pem -alias ${truststore_plugins_alias} -keystore ${ranger_admin_truststore_location} -storepass changeit -noprompt

# Setup Truststore - add Solr cert to Ranger Admin
keytool -delete -alias ${truststore_solr_alias} -keystore ${ranger_admin_truststore_location} -storepass changeit -noprompt || true
keytool -import -file ${solr_certs_path}/trustedCertificates.pem -alias ${truststore_solr_alias} -keystore ${ranger_admin_truststore_location} -storepass changeit -noprompt

# Setup Truststore - add RangerServer cert
keytool -delete -alias ${truststore_admin_alias} -keystore ${ranger_admin_truststore_location} -storepass changeit -noprompt || true
keytool -import -file ${ranger_server_certs_path}/trustedCertificates.pem -alias ${truststore_admin_alias} -keystore ${ranger_admin_truststore_location} -storepass changeit -noprompt

# Setup Keystore SOLR
mkdir -p /etc/solr/conf

openssl pkcs12 -export -in ${solr_certs_path}/certificateChain.pem -inkey ${solr_certs_path}/privateKey.pem -chain -CAfile ${solr_certs_path}/trustedCertificates.pem -name ${solr_keystore_alias} -out ${solr_certs_path}/keystore.p12 -password pass:${solr_keystore_password}
keytool -delete -alias ${solr_keystore_alias} -keystore ${solr_keystore_location} -storepass ${solr_keystore_password} -noprompt  || true
keytool -importkeystore -deststorepass ${solr_keystore_password} -destkeystore ${solr_keystore_location} -srckeystore ${solr_certs_path}/keystore.p12 -srcstoretype PKCS12 -srcstorepass ${solr_keystore_password}


#===============================================================================
# Database setup
#===============================================================================
yum -y install mariadb

mysql -h $RANGER_DB_HOST -u $RANGER_DB_ADMIN -p$RANGER_DB_ADMIN_PASSWORD -e "CREATE DATABASE IF NOT EXISTS $RANGER_DB_SCHEMA;"
mysql -h $RANGER_DB_HOST -u $RANGER_DB_ADMIN -p$RANGER_DB_ADMIN_PASSWORD -e "CREATE USER IF NOT EXISTS '$RANGER_DB_USER'@'localhost' IDENTIFIED BY '$RANGER_DB_USER_PASSWORD';"
mysql -h $RANGER_DB_HOST -u $RANGER_DB_ADMIN -p$RANGER_DB_ADMIN_PASSWORD -e "GRANT ALL PRIVILEGES ON \`%\`.* TO '$RANGER_DB_USER'@'localhost';"
mysql -h $RANGER_DB_HOST -u $RANGER_DB_ADMIN -p$RANGER_DB_ADMIN_PASSWORD -e "GRANT ALL PRIVILEGES ON \`%\`.* TO '$RANGER_DB_USER'@'localhost' WITH GRANT OPTION;"
mysql -h $RANGER_DB_HOST -u $RANGER_DB_ADMIN -p$RANGER_DB_ADMIN_PASSWORD -e "CREATE USER IF NOT EXISTS '$RANGER_DB_USER'@'%' IDENTIFIED BY '$RANGER_DB_USER_PASSWORD';"
mysql -h $RANGER_DB_HOST -u $RANGER_DB_ADMIN -p$RANGER_DB_ADMIN_PASSWORD -e "GRANT ALL PRIVILEGES ON \`%\`.* TO '$RANGER_DB_USER'@'%';"
mysql -h $RANGER_DB_HOST -u $RANGER_DB_ADMIN -p$RANGER_DB_ADMIN_PASSWORD -e "GRANT ALL PRIVILEGES ON \`%\`.* TO '$RANGER_DB_USER'@'%' WITH GRANT OPTION;"
mysql -h $RANGER_DB_HOST -u $RANGER_DB_ADMIN -p$RANGER_DB_ADMIN_PASSWORD -e "FLUSH PRIVILEGES;"

#===============================================================================
# Apache Ranger Requirements
#===============================================================================
yum install -y openldap openldap-clients openldap-servers

rm -rf $installpath && mkdir -p $installpath/hadoop && cd $installpath
aws s3 cp $ranger_s3bucket/$ranger_admin_server.tar.gz .
aws s3 cp $ranger_s3bucket/$ranger_user_sync.tar.gz .
aws s3 cp $ranger_s3bucket/solr_for_audit_setup.tar.gz .
wget $mysql_jar_location

#===============================================================================
# Apache Ranger Admin Configuration
#===============================================================================
mkdir $ranger_admin_server
tar -xvf $ranger_admin_server.tar.gz -C $ranger_admin_server --strip-components=1
cd $ranger_admin_server

# Database conf
sed -i "s|SQL_CONNECTOR_JAR=.*|SQL_CONNECTOR_JAR=$installpath/$mysql_jar|g" install.properties
sed -i "s|db_root_user=.*|db_root_user=${RANGER_DB_ADMIN}|g" install.properties
sed -i "s|db_root_password=.*|db_root_password=${RANGER_DB_ADMIN_PASSWORD}|g" install.properties
sed -i "s|db_host=.*|db_host=${RANGER_DB_HOST}|g" install.properties
sed -i "s|db_name=.*|db_name=${RANGER_DB_SCHEMA}|g" install.properties
sed -i "s|db_user=.*|db_user=${RANGER_DB_USER}|g" install.properties
sed -i "s|db_password=.*|db_password=${RANGER_DB_USER_PASSWORD}|g" install.properties
sed -i "s|audit_db_password=.*|audit_db_password=rangerlogger|g" install.properties

# Update log4j to debug
sed -i "s|info|debug|g" ews/webapp/WEB-INF/log4j.properties

# SSL conf
sed -i "s|policymgr_external_url=.*|policymgr_external_url=https://$current_hostname:6182|g" install.properties
sed -i "s|policymgr_http_enabled=.*|policymgr_http_enabled=false|g" install.properties
sed -i "s|policymgr_https_keystore_file=.*|policymgr_https_keystore_file=${ranger_admin_keystore_location}|g" install.properties
sed -i "s|policymgr_https_keystore_keyalias=.*|policymgr_https_keystore_keyalias=${ranger_admin_keystore_alias}|g" install.properties
sed -i "s|policymgr_https_keystore_password=.*|policymgr_https_keystore_password=${ranger_admin_keystore_password}|g" install.properties
sed -i "s|audit_solr_urls=.*|audit_solr_urls=https://$current_hostname:8984/solr/ranger_audits|g" install.properties
sed -i "s|audit_store=.*|audit_store=solr|g" install.properties

# LDAP properties
sed -i "s|authentication_method=.*|authentication_method=LDAP|g" install.properties
sed -i "s|xa_ldap_url=.*|xa_ldap_url=$ldap_server_url|g" install.properties
sed -i "s|xa_ldap_userDNpattern=.*|xa_ldap_userDNpattern=uid={0},cn=users,$ldap_base_dn|g" install.properties
sed -i "s|xa_ldap_groupSearchBase=.*|xa_ldap_groupSearchBase=$ldap_base_dn|g" install.properties
sed -i "s|xa_ldap_groupSearchFilter=.*|xa_ldap_groupSearchFilter=objectclass=group|g" install.properties
sed -i "s|xa_ldap_groupRoleAttribute=.*|xa_ldap_groupRoleAttribute=cn|g" install.properties
sed -i "s|xa_ldap_base_dn=.*|xa_ldap_base_dn=$ldap_base_dn|g" install.properties
sed -i "s|xa_ldap_bind_dn=.*|xa_ldap_bind_dn=$ldap_bind_user_dn|g" install.properties
sed -i "s|xa_ldap_bind_password=.*|xa_ldap_bind_password=$ldap_bind_password|g" install.properties
sed -i "s|xa_ldap_referral=.*|xa_ldap_referral=ignore|g" install.properties
sed -i "s|xa_ldap_userSearchFilter=.*|xa_ldap_userSearchFilter=(sAMAccountName={0})|g" install.properties

# Kerberos properties
sed -i "s|admin_principal=.*|admin_principal=Admin@awsemr.com)|g" install.properties
sed -i "s|admin_keytab=.*|admin_keytab=/etc/awsadmin.keytab|g" install.properties
sed -i "s|lookup_principal=.*|lookup_principal=Admin@awsemr.com|g" install.properties
sed -i "s|lookup_keytab=.*|lookup_keytab=/etc/awsadmin.keytab|g" install.properties

# CHECKTHIS - FIX FOR java.lang.NoClassDefFoundError: org/apache/htrace/core/Tracer$Builder
cp /usr/lib/ranger/$ranger_admin_server/ews/webapp/WEB-INF/lib/htrace-core* /usr/lib/ranger/$ranger_admin_server/cred/lib
cp /usr/lib/ranger/$ranger_admin_server/ews/webapp/WEB-INF/lib/commons-configuration* /usr/lib/ranger/$ranger_admin_server/cred/lib

# Install the spark ranger plugin
mkdir -p /usr/lib/ranger/$ranger_admin_server/ews/webapp/WEB-INF/classes/ranger-plugins/amazon-emr-spark
cp -r /usr/lib/ranger/$ranger_admin_server/ews/webapp/WEB-INF/classes/ranger-plugins/hive/* /usr/lib/ranger/$ranger_admin_server/ews/webapp/WEB-INF/classes/ranger-plugins/amazon-emr-spark/

chmod +x setup.sh
./setup.sh

# CHECKTHIS - FIX FOR Unable to get the Credential Provider from the Configuration when launching the server
sed -i "s|.*rangeradmin.jceks.*|<value>localjceks://file//usr/lib/ranger/$ranger_admin_server/ews/webapp/WEB-INF/classes/conf/.jceks/rangeradmin.jceks</value>|g" /usr/lib/ranger/$ranger_admin_server/ews/webapp/WEB-INF/classes/conf/ranger-admin-default-site.xml


#===============================================================================
# Apache Ranger Usersync Configuration
#===============================================================================
cd $installpath
mkdir $ranger_user_sync
tar -xvf $ranger_user_sync.tar.gz -C $ranger_user_sync --strip-components=1
cp ./$ranger_admin_server/ews/webapp/WEB-INF/lib/jackson-* ./$ranger_user_sync/lib/
chown ranger:ranger ./$ranger_user_sync/lib/*
chmod 755 ./$ranger_user_sync/lib/*

cd $ranger_user_sync

sed -i "s|POLICY_MGR_URL =.*|POLICY_MGR_URL=https://$current_hostname:6182|g" install.properties
sed -i "s|POLICY_MGR_URL=.*|POLICY_MGR_URL=https://$current_hostname:6182|g" install.properties
sed -i "s|SYNC_SOURCE =.*|SYNC_SOURCE=ldap|g" install.properties
sed -i "s|SYNC_LDAP_URL =.*|SYNC_LDAP_URL=$ldap_server_url|g" install.properties
sed -i "s|SYNC_LDAP_BIND_DN =.*|SYNC_LDAP_BIND_DN=$ldap_bind_user_dn|g" install.properties
sed -i "s|SYNC_LDAP_BIND_PASSWORD =.*|SYNC_LDAP_BIND_PASSWORD=$ldap_bind_password|g" install.properties

sed -i "s|SYNC_LDAP_SEARCH_BASE =.*|SYNC_LDAP_SEARCH_BASE=$ldap_base_dn|g" install.properties
sed -i "s|SYNC_LDAP_USER_SEARCH_BASE =.*|SYNC_LDAP_USER_SEARCH_BASE=$ldap_base_dn|g" install.properties
sed -i "s|SYNC_LDAP_USER_SEARCH_FILTER =.*|SYNC_LDAP_USER_SEARCH_FILTER=sAMAccountName=*|g" install.properties
sed -i "s|SYNC_LDAP_USER_NAME_ATTRIBUTE =.*|SYNC_LDAP_USER_NAME_ATTRIBUTE=sAMAccountName|g" install.properties
sed -i "s|SYNC_INTERVAL =.*|SYNC_INTERVAL=2|g" install.properties
# SSL conf
sed -i "s|AUTH_SSL_TRUSTSTORE_FILE=.*|AUTH_SSL_TRUSTSTORE_FILE=$ranger_admin_truststore_location|g" install.properties
sed -i "s|AUTH_SSL_TRUSTSTORE_PASSWORD=.*|AUTH_SSL_TRUSTSTORE_PASSWORD=$ranger_admin_truststore_password|g" install.properties

cp /usr/lib/ranger/$ranger_admin_server/ews/webapp/WEB-INF/lib/commons-configuration* /usr/lib/ranger/$ranger_user_sync/lib/

chmod +x setup.sh
./setup.sh

#===============================================================================
# Apache Solr Configuration
#===============================================================================

# Download the install solr for ranger
cd $installpath
mkdir solr_for_audit_setup
tar -xvf solr_for_audit_setup.tar.gz -C solr_for_audit_setup --strip-components=1
cd solr_for_audit_setup

solr_standalone_conf_script="/usr/lib/ranger/solr_for_audit_setup/solr_standalone/scripts/solr.in.sh.j2"

sed -i "s|SOLR_HOST_URL=.*|SOLR_HOST_URL=https://$current_hostname:8984|g" install.properties
sed -i "s|SOLR_RANGER_PORT=.*|SOLR_RANGER_PORT=8984|g" install.properties

sed -i "s|.*SOLR_SSL_KEY_STORE=.*|SOLR_SSL_KEY_STORE=${solr_keystore_location}|g" ${solr_standalone_conf_script}
sed -i "s|.*SOLR_SSL_KEY_STORE_PASSWORD=.*|SOLR_SSL_KEY_STORE_PASSWORD=${solr_keystore_password}|g" ${solr_standalone_conf_script}
sed -i "s|.*SOLR_SSL_TRUST_STORE=.*|SOLR_SSL_TRUST_STORE=$JAVA_HOME/lib/security/cacerts|g" ${solr_standalone_conf_script}
sed -i "s|.*SOLR_SSL_TRUST_STORE_PASSWORD=.*|SOLR_SSL_TRUST_STORE_PASSWORD=changeit|g" ${solr_standalone_conf_script}
sed -i "s|.*SOLR_SSL_NEED_CLIENT_AUTH=.*|SOLR_SSL_NEED_CLIENT_AUTH=false|g" ${solr_standalone_conf_script}
sed -i "s|.*SOLR_SSL_WANT_CLIENT_AUTH=.*|SOLR_SSL_WANT_CLIENT_AUTH=false|g" ${solr_standalone_conf_script}
sed -i "s|SOLR_MAX_MEM=.*|SOLR_MAX_MEM=4g|g" install.properties
sed -i 's/+90DAYS/+2DAYS/g' conf/solrconfig.xml
chmod +x setup.sh
./setup.sh

mkdir -p /usr/lib/ranger/logs/admin/
ln -sfn /usr/lib/ranger/$ranger_admin_server/ews/logs /usr/lib/ranger/logs/admin/logs


#===============================================================================
# Launch Services
#===============================================================================

#Start Ranger Admin
echo "log4j.appender.xa_log_policy_appender=org.apache.log4j.DailyRollingFileAppender
log4j.appender.xa_log_policy_appender.file=\${logdir}/ranger_admin_policy_updates.log
log4j.appender.xa_log_policy_appender.datePattern='.'yyyy-MM-dd
log4j.appender.xa_log_policy_appender.append=true
log4j.appender.xa_log_policy_appender.layout=org.apache.log4j.PatternLayout
log4j.appender.xa_log_policy_appender.layout.ConversionPattern=%d [%t] %-5p %C{6} (%F:%L) - %m%n

log4j.category.org.apache.ranger.rest.ServiceREST=debug,xa_log_policy_appender
log4j.additivity.org.apache.ranger.rest.ServiceREST=false" >> /usr/lib/ranger/$ranger_admin_server/ews/webapp/WEB-INF/log4j.properties
ln -s /usr/lib/ranger/$ranger_admin_server/ews/webapp/WEB-INF/classes/ranger-plugins/hive/ranger-hive-plugin-$ranger_download_version* /usr/lib/ranger/$ranger_admin_server/ews/webapp/WEB-INF/lib/
ln -s /usr/lib/ranger/$ranger_admin_server/ews/webapp/WEB-INF/classes/ranger-plugins/hdfs/ranger-hdfs-plugin-$ranger_download_version* /usr/lib/ranger/$ranger_admin_server/ews/webapp/WEB-INF/lib/

# Setup the Spark Ranger plugin definition
rm -rf /usr/lib/ranger/$ranger_admin_server/ews/webapp/WEB-INF/classes/ranger-plugins/amazon-emr-spark
mkdir -p /usr/lib/ranger/$ranger_admin_server/ews/webapp/WEB-INF/classes/ranger-plugins/amazon-emr-spark
wget -O /tmp/ranger-spark-plugin-2.x.jar https://s3.amazonaws.com/elasticmapreduce/ranger/service-definitions/version-2.0/ranger-spark-plugin-2.x.jar
mv /tmp/ranger-spark-plugin-2.x.jar /usr/lib/ranger/$ranger_admin_server/ews/webapp/WEB-INF/classes/ranger-plugins/amazon-emr-spark/

# Setup the EMRFS Ranger plugin definition
rm -rf /usr/lib/ranger/$ranger_admin_server/ews/webapp/WEB-INF/classes/ranger-plugins/amazon-emr-emrfs
mkdir -p /usr/lib/ranger/$ranger_admin_server/ews/webapp/WEB-INF/classes/ranger-plugins/amazon-emr-emrfs
wget -O /tmp/ranger-emrfs-s3-plugin-2.x.jar https://s3.amazonaws.com/elasticmapreduce/ranger/service-definitions/version-2.0/ranger-emr-emrfs-plugin-2.x.jar
mv /tmp/ranger-emrfs-s3-plugin-2.x.jar /usr/lib/ranger/$ranger_admin_server/ews/webapp/WEB-INF/classes/ranger-plugins/amazon-emr-emrfs/


#CHECKTHIS - wrong path
cp /usr/lib/ranger/$ranger_admin_server/ews/webapp/WEB-INF/classes/ranger-plugins/hive/* /usr/lib/ranger/$ranger_admin_server/ews/webapp/WEB-INF/lib/ || true

#Setup proper owner for keytabs locations
chown solr:solr -R /etc/solr
chown ranger:ranger -R /etc/ranger

#cleanup
rm -rf ${certs_path}

/usr/bin/ranger-admin stop || true
/usr/bin/ranger-admin start
i=0;
while ! timeout 1 bash -c "echo > /dev/tcp/$current_hostname/6182"; do
        sleep 10;
        i=$((i + 1))
        if (( i > 6 )); then
                break;
        fi
done

# Start Ranger Usersync
/usr/bin/ranger-usersync stop || true
/usr/bin/ranger-usersync start

# Update the Ranger service def
installpath=/tmp/ranger-plugins-servicedef/

# Update repo/policies
rm -rf $installpath
mkdir -p $installpath
chmod -R 777 $installpath
cd $installpath
aws s3 cp $s3bucket/${project_version}/inputdata/service-definition/$ranger_service_def_ver/ . --recursive --exclude "*" --include "*.json" --region us-east-1
for i in `find . -name "ranger-servicedef-*.json" -type f`; do
    file_name=`echo "$i" | cut -c 3-`
    echo "$file_name"
    curl -iv --insecure -u admin:admin -X POST -d @$file_name -H "Accept: application/json" -H "Content-Type: application/json" -k $HTTP_URL/service/public/v2/api/servicedef
done

# Restart SOLR
/opt/solr/ranger_audit_server/scripts/stop_solr.sh || true
/opt/solr/ranger_audit_server/scripts/start_solr.sh
