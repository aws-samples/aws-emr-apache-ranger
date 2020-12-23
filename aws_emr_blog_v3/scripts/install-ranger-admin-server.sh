#!/bin/bash
set -euo pipefail
set -x
#================================================================
# Script to setup the Apache Ranger Server
#================================================================
#% SYNOPSIS
#+    install-ranger-admin-server.sh <ldap_ip_address> <ldap_base_dn> <ldap_bind_user_dn> <ldap_bind_password> <ranger_version> <s3bucket> <project_version> <db_host_name> <db_root_password>
#%
#% DESCRIPTION
#%    Downloads the scripts used in EMR steps
#%
#% EXAMPLES
#%    install-ranger-admin-server.sh <ldap_ip_address> dc=awsemr,dc=com binduser@awsemr.com <ldap_bind_password> 2.0 s3://aws-bigdata-blog/artifacts/aws-blog-emr-ranger 3.0 <rds-database-name>.rds.amazonaws.com <db_root_password>
#%
#================================================================
#- IMPLEMENTATION
#-    version         install-ranger-admin-server.sh 1.0
#-    author          Varun Bhamidimarri, Stefano Sandonà
#-    license         MIT license
#-
#
#================================================================
#================================================================

sudo yum -y install java-1.8.0
sudo yum -y remove java-1.7.0-openjdk
sudo yum -y install krb5-workstation krb5-libs krb5-auth-dialog

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
db_host_name=$8
db_root_password=$9
ldap_server_url=ldap://$ldap_ip_address
ranger_service_def_ver=2.0.0
#ldap_admin_user=${10}
#ldap_domain_dns=${11}
#ldap_admin_password=${12}

if [ "$ranger_version" == "2.0" ]; then
   ranger_download_version=2.1.0-SNAPSHOT
   ranger_service_def_ver=2.0.0
else
   ranger_download_version=1.0.1
fi

#sudo sed 's/awsemr.com/ec2.internal awsemr.com\nnameserver 10.0.0.2\n/g'

ranger_s3bucket=$s3bucket/ranger/ranger-$ranger_download_version
ranger_admin_server=ranger-$ranger_download_version-admin
ranger_user_sync=ranger-$ranger_download_version-usersync

mysql_jar_location=$s3bucket/ranger/ranger-$ranger_download_version/mysql-connector-java-5.1.39.jar
mysql_jar=mysql-connector-java-5.1.39.jar


#certs_s3_location=${s3bucket}/${project_version}/emr-tls/

certs_path="/tmp/certs"

current_hostname=$(hostname -f)

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

#Download certs
rm -rf ${certs_path}
mkdir -p ${certs_path}
#aws s3 sync ${certs_s3_location} ${certs_path}

mkdir -p ${ranger_agents_certs_path}
mkdir -p ${ranger_server_certs_path}
mkdir -p ${solr_certs_path}

#unzip -o ${ranger_agents_certs_path}.zip -d ${ranger_agents_certs_path}
#unzip -o ${ranger_server_certs_path}.zip -d ${ranger_server_certs_path}
#unzip -o ${solr_certs_path}.zip -d ${solr_certs_path}

## Using Secrets Manager to get the private Key and certs
sudo yum -y install https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm || true
sudo yum install jq -y
aws secretsmanager get-secret-value --secret-id emr/rangerServerPrivateKey --version-stage AWSCURRENT --region us-east-1 | jq -r ".SecretString"  > ${ranger_server_certs_path}/privateKey.pem
aws secretsmanager get-secret-value --secret-id emr/rangerGAservercert --version-stage AWSCURRENT --region us-east-1 | jq -r ".SecretString"  > ${ranger_server_certs_path}/trustedCertificates.pem
aws secretsmanager get-secret-value --secret-id emr/rangerPluginCert --version-stage AWSCURRENT --region us-east-1 | jq -r ".SecretString"  > ${ranger_agents_certs_path}/trustedCertificates.pem
aws secretsmanager get-secret-value --secret-id emr/rangerSolrCert --version-stage AWSCURRENT --region us-east-1 | jq -r ".SecretString"  > ${solr_certs_path}/certificateChain.pem
aws secretsmanager get-secret-value --secret-id emr/rangerSolrPrivateKey --version-stage AWSCURRENT --region us-east-1 | jq -r ".SecretString"  > ${solr_certs_path}/privateKey.pem
aws secretsmanager get-secret-value --secret-id emr/rangerSolrTrustedCert --version-stage AWSCURRENT --region us-east-1 | jq -r ".SecretString"  > ${solr_certs_path}/trustedCertificates.pem

sudo mkdir -p /etc/ranger/admin/conf

#Setup Keystore for RangerAdmin
openssl pkcs12 -export -in ${ranger_server_certs_path}/trustedCertificates.pem -inkey ${ranger_server_certs_path}/privateKey.pem -chain -CAfile ${ranger_server_certs_path}/trustedCertificates.pem -name ${ranger_admin_keystore_alias} -out ${ranger_server_certs_path}/keystore.p12 -password pass:${ranger_admin_keystore_password}
keytool -delete -alias ${ranger_admin_keystore_alias} -keystore ${ranger_admin_keystore_location} -storepass ${ranger_admin_keystore_password} -noprompt || true
sudo keytool -importkeystore -deststorepass ${ranger_admin_keystore_password} -destkeystore ${ranger_admin_keystore_location} -srckeystore ${ranger_server_certs_path}/keystore.p12 -srcstoretype PKCS12 -srcstorepass ${ranger_admin_keystore_password}
#sudo chown ranger:ranger -R /etc/ranger

#Setup Truststore - add agent cert to Ranger Admin
keytool -delete -alias ${truststore_plugins_alias} -keystore ${ranger_admin_truststore_location} -storepass changeit -noprompt || true
sudo keytool -import -file ${ranger_agents_certs_path}/trustedCertificates.pem -alias ${truststore_plugins_alias} -keystore ${ranger_admin_truststore_location} -storepass changeit -noprompt

#Setup Truststore - add Solr cert to Ranger Admin
keytool -delete -alias ${truststore_solr_alias} -keystore ${ranger_admin_truststore_location} -storepass changeit -noprompt || true
sudo keytool -import -file ${solr_certs_path}/trustedCertificates.pem -alias ${truststore_solr_alias} -keystore ${ranger_admin_truststore_location} -storepass changeit -noprompt

#Setup Truststore - add RangerServer cert
keytool -delete -alias ${truststore_admin_alias} -keystore ${ranger_admin_truststore_location} -storepass changeit -noprompt || true
sudo keytool -import -file ${ranger_server_certs_path}/trustedCertificates.pem -alias ${truststore_admin_alias} -keystore ${ranger_admin_truststore_location} -storepass changeit -noprompt

#Setup Keystore SOLR

sudo mkdir -p /etc/solr/conf

openssl pkcs12 -export -in ${solr_certs_path}/certificateChain.pem -inkey ${solr_certs_path}/privateKey.pem -chain -CAfile ${solr_certs_path}/trustedCertificates.pem -name ${solr_keystore_alias} -out ${solr_certs_path}/keystore.p12 -password pass:${solr_keystore_password}
keytool -delete -alias ${solr_keystore_alias} -keystore ${solr_keystore_location} -storepass ${solr_keystore_password} -noprompt  || true
sudo keytool -importkeystore -deststorepass ${solr_keystore_password} -destkeystore ${solr_keystore_location} -srckeystore ${solr_certs_path}/keystore.p12 -srcstoretype PKCS12 -srcstorepass ${solr_keystore_password}

# Setup
yum install -y openldap openldap-clients openldap-servers
# Setup LDAP users
#aws s3 cp $s3bucket/${project_version}/inputdata/load-users-new.ldf .
#aws s3 cp $s3bucket/${project_version}/inputdata/modify-users-new.ldf .
#aws s3 cp $s3bucket/${project_version}/scripts/create-users-using-ldap.sh .
#chmod +x create-users-using-ldap.sh
#./create-users-using-ldap.sh $ldap_ip_address $ldap_admin_user@$ldap_domain_dns $ldap_admin_password $ldap_base_dn || true
#Install mySQL
yum -y install mysql-server
service mysqld start
chkconfig mysqld on
mysqladmin -u root password rangeradmin || true
rm -rf $installpath
mkdir -p $installpath/hadoop
cd $installpath
aws s3 cp $ranger_s3bucket/$ranger_admin_server.tar.gz .
aws s3 cp $ranger_s3bucket/$ranger_user_sync.tar.gz .
aws s3 cp $mysql_jar_location .
aws s3 cp $ranger_s3bucket/solr_for_audit_setup.tar.gz .
#Update ranger admin install.properties
mkdir $ranger_admin_server
tar -xvf $ranger_admin_server.tar.gz -C $ranger_admin_server --strip-components=1

cd $ranger_admin_server

sudo sed -i "s|SQL_CONNECTOR_JAR=.*|SQL_CONNECTOR_JAR=$installpath/$mysql_jar|g" install.properties

DB_ROOT_USERNAME="root"

RDS_RANGER_SCHEMA_DBNAME="rangerdb"
RDS_RANGER_SCHEMA_DBUSER="rangeradmin"
RDS_RANGER_SCHEMA_DBPASSWORD="rangeradmin"

MYSQL="/usr/bin/mysql"

_generateSQLGrantsAndCreateUser()
{
    touch ~/generate_grants.sql
    HOSTNAMEI=`hostname -I`
    HOSTNAMEI=`echo ${HOSTNAMEI}`
    cat >~/generate_grants.sql <<EOF
CREATE USER IF NOT EXISTS '${RDS_RANGER_SCHEMA_DBUSER}'@'localhost' IDENTIFIED BY '${RDS_RANGER_SCHEMA_DBPASSWORD}';
CREATE DATABASE IF NOT EXISTS ${RDS_RANGER_SCHEMA_DBNAME};
GRANT ALL PRIVILEGES ON \`%\`.* TO '${RDS_RANGER_SCHEMA_DBUSER}'@'localhost';
CREATE USER IF NOT EXISTS '${RDS_RANGER_SCHEMA_DBUSER}'@'%' IDENTIFIED BY '${RDS_RANGER_SCHEMA_DBPASSWORD}';
GRANT ALL PRIVILEGES ON \`%\`.* TO '${RDS_RANGER_SCHEMA_DBUSER}'@'%';
CREATE USER IF NOT EXISTS '${RDS_RANGER_SCHEMA_DBUSER}'@'${HOSTNAMEI}' IDENTIFIED BY '${RDS_RANGER_SCHEMA_DBPASSWORD}';
GRANT ALL PRIVILEGES ON \`%\`.* TO '${RDS_RANGER_SCHEMA_DBUSER}'@'${HOSTNAMEI}';
GRANT ALL PRIVILEGES ON \`%\`.* TO '${RDS_RANGER_SCHEMA_DBUSER}'@'${HOSTNAMEI}' WITH GRANT OPTION;
GRANT ALL PRIVILEGES ON \`%\`.* TO '${RDS_RANGER_SCHEMA_DBUSER}'@'localhost' WITH GRANT OPTION;
GRANT ALL PRIVILEGES ON \`%\`.* TO '${RDS_RANGER_SCHEMA_DBUSER}'@'%' WITH GRANT OPTION;
FLUSH PRIVILEGES;
exit
EOF

}
_setupMySQLDatabaseAndPrivileges()
{
    HOSTNAMEI=`hostname -I`
    ${MYSQL} -h ${db_host_name} -u ${DB_ROOT_USERNAME} -p${db_root_password} < ~/generate_grants.sql
    echo $?
}

_generateSQLGrantsAndCreateUser
_setupMySQLDatabaseAndPrivileges

sudo sed -i "s|db_root_user=.*|db_root_user=${DB_ROOT_USERNAME}|g" install.properties
sudo sed -i "s|db_root_password=.*|db_root_password=${db_root_password}|g" install.properties
sudo sed -i "s|db_host=.*|db_host=${db_host_name}|g" install.properties
sudo sed -i "s|db_name=.*|db_name=${RDS_RANGER_SCHEMA_DBNAME}|g" install.properties
sudo sed -i "s|db_user=.*|db_user=${RDS_RANGER_SCHEMA_DBUSER}|g" install.properties
sudo sed -i "s|db_password=.*|db_password=${RDS_RANGER_SCHEMA_DBPASSWORD}|g" install.properties
sudo sed -i "s|audit_db_password=.*|audit_db_password=rangerlogger|g" install.properties

## Update log4j to debug
sudo sed -i "s|info|debug|g" ews/webapp/WEB-INF/log4j.properties


# SSL conf
sudo sed -i "s|policymgr_external_url=.*|policymgr_external_url=https://$current_hostname:6182|g" install.properties
sudo sed -i "s|policymgr_http_enabled=.*|policymgr_http_enabled=false|g" install.properties
sudo sed -i "s|policymgr_https_keystore_file=.*|policymgr_https_keystore_file=${ranger_admin_keystore_location}|g" install.properties
sudo sed -i "s|policymgr_https_keystore_keyalias=.*|policymgr_https_keystore_keyalias=${ranger_admin_keystore_alias}|g" install.properties
sudo sed -i "s|policymgr_https_keystore_password=.*|policymgr_https_keystore_password=${ranger_admin_keystore_password}|g" install.properties
sudo sed -i "s|audit_solr_urls=.*|audit_solr_urls=https://$current_hostname:8984/solr/ranger_audits|g" install.properties
sudo sed -i "s|audit_store=.*|audit_store=solr|g" install.properties

#sudo sed -i "s|audit_solr_urls=.*|audit_solr_urls=http://localhost:8983/solr/ranger_audits|g" install.properties
#sudo sed -i "s|policymgr_external_url=.*|policymgr_external_url=http://$hostname:6080|g" install.properties

#Update LDAP properties
sudo sed -i "s|authentication_method=.*|authentication_method=LDAP|g" install.properties
sudo sed -i "s|xa_ldap_url=.*|xa_ldap_url=$ldap_server_url|g" install.properties
sudo sed -i "s|xa_ldap_userDNpattern=.*|xa_ldap_userDNpattern=uid={0},cn=users,$ldap_base_dn|g" install.properties
sudo sed -i "s|xa_ldap_groupSearchBase=.*|xa_ldap_groupSearchBase=$ldap_base_dn|g" install.properties
sudo sed -i "s|xa_ldap_groupSearchFilter=.*|xa_ldap_groupSearchFilter=objectclass=group|g" install.properties
sudo sed -i "s|xa_ldap_groupRoleAttribute=.*|xa_ldap_groupRoleAttribute=cn|g" install.properties
sudo sed -i "s|xa_ldap_base_dn=.*|xa_ldap_base_dn=$ldap_base_dn|g" install.properties
sudo sed -i "s|xa_ldap_bind_dn=.*|xa_ldap_bind_dn=$ldap_bind_user_dn|g" install.properties
sudo sed -i "s|xa_ldap_bind_password=.*|xa_ldap_bind_password=$ldap_bind_password|g" install.properties
sudo sed -i "s|xa_ldap_referral=.*|xa_ldap_referral=ignore|g" install.properties
sudo sed -i "s|xa_ldap_userSearchFilter=.*|xa_ldap_userSearchFilter=(sAMAccountName={0})|g" install.properties

#Kerberos properties
sudo sed -i "s|admin_principal=.*|admin_principal=Admin@awsemr.com)|g" install.properties
sudo sed -i "s|admin_keytab=.*|admin_keytab=/etc/awsadmin.keytab|g" install.properties
sudo sed -i "s|lookup_principal=.*|lookup_principal=Admin@awsemr.com|g" install.properties
sudo sed -i "s|lookup_keytab=.*|lookup_keytab=/etc/awsadmin.keytab|g" install.properties

#CHECKTHIS - FIX FOR java.lang.NoClassDefFoundError: org/apache/htrace/core/Tracer$Builder
sudo cp /usr/lib/ranger/$ranger_admin_server/ews/webapp/WEB-INF/lib/htrace-core* /usr/lib/ranger/$ranger_admin_server/cred/lib
sudo cp /usr/lib/ranger/$ranger_admin_server/ews/webapp/WEB-INF/lib/commons-configuration* /usr/lib/ranger/$ranger_admin_server/cred/lib

## Install the spark ranger plugin
sudo mkdir -p /usr/lib/ranger/$ranger_admin_server/ews/webapp/WEB-INF/classes/ranger-plugins/amazon-emr-spark
cp -r /usr/lib/ranger/$ranger_admin_server/ews/webapp/WEB-INF/classes/ranger-plugins/hive/* /usr/lib/ranger/$ranger_admin_server/ews/webapp/WEB-INF/classes/ranger-plugins/amazon-emr-spark/

chmod +x setup.sh
./setup.sh

#CHECKTHIS - FIX FOR Unable to get the Credential Provider from the Configuration when launching the server
sudo sed -i "s|.*rangeradmin.jceks.*|<value>localjceks://file//usr/lib/ranger/$ranger_admin_server/ews/webapp/WEB-INF/classes/conf/.jceks/rangeradmin.jceks</value>|g" /usr/lib/ranger/$ranger_admin_server/ews/webapp/WEB-INF/classes/conf/ranger-admin-default-site.xml

#Update ranger usersync install.properties
cd $installpath
mkdir $ranger_user_sync
tar -xvf $ranger_user_sync.tar.gz -C $ranger_user_sync --strip-components=1
cp ./$ranger_admin_server/ews/webapp/WEB-INF/lib/jackson-* ./$ranger_user_sync/lib/
chown ranger:ranger ./$ranger_user_sync/lib/*
chmod 755 ./$ranger_user_sync/lib/*

cd $ranger_user_sync


#sudo sed -i "s|POLICY_MGR_URL =.*|POLICY_MGR_URL=http://$hostname:6080|g" install.properties

sudo sed -i "s|POLICY_MGR_URL =.*|POLICY_MGR_URL=https://$current_hostname:6182|g" install.properties
sudo sed -i "s|POLICY_MGR_URL=.*|POLICY_MGR_URL=https://$current_hostname:6182|g" install.properties
sudo sed -i "s|SYNC_SOURCE =.*|SYNC_SOURCE=ldap|g" install.properties
sudo sed -i "s|SYNC_LDAP_URL =.*|SYNC_LDAP_URL=$ldap_server_url|g" install.properties
sudo sed -i "s|SYNC_LDAP_BIND_DN =.*|SYNC_LDAP_BIND_DN=$ldap_bind_user_dn|g" install.properties
sudo sed -i "s|SYNC_LDAP_BIND_PASSWORD =.*|SYNC_LDAP_BIND_PASSWORD=$ldap_bind_password|g" install.properties


sudo sed -i "s|SYNC_LDAP_SEARCH_BASE =.*|SYNC_LDAP_SEARCH_BASE=$ldap_base_dn|g" install.properties
sudo sed -i "s|SYNC_LDAP_USER_SEARCH_BASE =.*|SYNC_LDAP_USER_SEARCH_BASE=$ldap_base_dn|g" install.properties
sudo sed -i "s|SYNC_LDAP_USER_SEARCH_FILTER =.*|SYNC_LDAP_USER_SEARCH_FILTER=sAMAccountName=*|g" install.properties
sudo sed -i "s|SYNC_LDAP_USER_NAME_ATTRIBUTE =.*|SYNC_LDAP_USER_NAME_ATTRIBUTE=sAMAccountName|g" install.properties
sudo sed -i "s|SYNC_INTERVAL =.*|SYNC_INTERVAL=2|g" install.properties
# SSL conf
sudo sed -i "s|AUTH_SSL_TRUSTSTORE_FILE=.*|AUTH_SSL_TRUSTSTORE_FILE=$ranger_admin_truststore_location|g" install.properties
sudo sed -i "s|AUTH_SSL_TRUSTSTORE_PASSWORD=.*|AUTH_SSL_TRUSTSTORE_PASSWORD=$ranger_admin_truststore_password|g" install.properties

sudo cp /usr/lib/ranger/$ranger_admin_server/ews/webapp/WEB-INF/lib/commons-configuration* /usr/lib/ranger/$ranger_user_sync/lib/

chmod +x setup.sh
./setup.sh

#Download the install solr for ranger
cd $installpath
mkdir solr_for_audit_setup
tar -xvf solr_for_audit_setup.tar.gz -C solr_for_audit_setup --strip-components=1
cd solr_for_audit_setup

solr_standalone_conf_script="/usr/lib/ranger/solr_for_audit_setup/solr_standalone/scripts/solr.in.sh.j2"

sudo sed -i "s|SOLR_HOST_URL=.*|SOLR_HOST_URL=https://$current_hostname:8984|g" install.properties
sudo sed -i "s|SOLR_RANGER_PORT=.*|SOLR_RANGER_PORT=8984|g" install.properties

sudo sed -i "s|.*SOLR_SSL_KEY_STORE=.*|SOLR_SSL_KEY_STORE=${solr_keystore_location}|g" ${solr_standalone_conf_script}
sudo sed -i "s|.*SOLR_SSL_KEY_STORE_PASSWORD=.*|SOLR_SSL_KEY_STORE_PASSWORD=${solr_keystore_password}|g" ${solr_standalone_conf_script}
sudo sed -i "s|.*SOLR_SSL_TRUST_STORE=.*|SOLR_SSL_TRUST_STORE=$JAVA_HOME/lib/security/cacerts|g" ${solr_standalone_conf_script}
sudo sed -i "s|.*SOLR_SSL_TRUST_STORE_PASSWORD=.*|SOLR_SSL_TRUST_STORE_PASSWORD=changeit|g" ${solr_standalone_conf_script}
sudo sed -i "s|.*SOLR_SSL_NEED_CLIENT_AUTH=.*|SOLR_SSL_NEED_CLIENT_AUTH=false|g" ${solr_standalone_conf_script}
sudo sed -i "s|.*SOLR_SSL_WANT_CLIENT_AUTH=.*|SOLR_SSL_WANT_CLIENT_AUTH=false|g" ${solr_standalone_conf_script}



#sudo sed -i "s|SOLR_HOST_URL=.*|SOLR_HOST_URL=http://$hostname:8983|g" install.properties
#sudo sed -i "s|SOLR_RANGER_PORT=.*|SOLR_RANGER_PORT=8983|g" install.properties
sudo sed -i "s|SOLR_MAX_MEM=.*|SOLR_MAX_MEM=4g|g" install.properties
sed -i 's/+90DAYS/+2DAYS/g' conf/solrconfig.xml
chmod +x setup.sh
./setup.sh

#Start Ranger Admin
sudo echo "log4j.appender.xa_log_policy_appender=org.apache.log4j.DailyRollingFileAppender
log4j.appender.xa_log_policy_appender.file=\${logdir}/ranger_admin_policy_updates.log
log4j.appender.xa_log_policy_appender.datePattern='.'yyyy-MM-dd
log4j.appender.xa_log_policy_appender.append=true
log4j.appender.xa_log_policy_appender.layout=org.apache.log4j.PatternLayout
log4j.appender.xa_log_policy_appender.layout.ConversionPattern=%d [%t] %-5p %C{6} (%F:%L) - %m%n

log4j.category.org.apache.ranger.rest.ServiceREST=debug,xa_log_policy_appender
log4j.additivity.org.apache.ranger.rest.ServiceREST=false" >> /usr/lib/ranger/$ranger_admin_server/ews/webapp/WEB-INF/log4j.properties
sudo ln -s /usr/lib/ranger/$ranger_admin_server/ews/webapp/WEB-INF/classes/ranger-plugins/hive/ranger-hive-plugin-$ranger_download_version* /usr/lib/ranger/$ranger_admin_server/ews/webapp/WEB-INF/lib/
sudo ln -s /usr/lib/ranger/$ranger_admin_server/ews/webapp/WEB-INF/classes/ranger-plugins/hdfs/ranger-hdfs-plugin-$ranger_download_version* /usr/lib/ranger/$ranger_admin_server/ews/webapp/WEB-INF/lib/

# Setup the Spark Ranger plugin definition
sudo rm -rf /usr/lib/ranger/$ranger_admin_server/ews/webapp/WEB-INF/classes/ranger-plugins/amazon-emr-spark
sudo mkdir -p /usr/lib/ranger/$ranger_admin_server/ews/webapp/WEB-INF/classes/ranger-plugins/amazon-emr-spark
sudo wget -O /tmp/ranger-spark-plugin-2.x.jar https://s3.amazonaws.com/elasticmapreduce/ranger/service-definitions/version-2.0/ranger-spark-plugin-2.x.jar
sudo mv /tmp/ranger-spark-plugin-2.x.jar /usr/lib/ranger/$ranger_admin_server/ews/webapp/WEB-INF/classes/ranger-plugins/amazon-emr-spark/

# Setup the EMRFS Ranger plugin definition
sudo rm -rf /usr/lib/ranger/$ranger_admin_server/ews/webapp/WEB-INF/classes/ranger-plugins/amazon-emr-emrfs
sudo mkdir -p /usr/lib/ranger/$ranger_admin_server/ews/webapp/WEB-INF/classes/ranger-plugins/amazon-emr-emrfs
sudo wget -O /tmp/ranger-emrfs-s3-plugin-2.x.jar wget https://s3.amazonaws.com/elasticmapreduce/ranger/service-definitions/version-2.0/ranger-emr-emrfs-plugin-2.x.jar
sudo mv /tmp/ranger-emrfs-s3-plugin-2.x.jar /usr/lib/ranger/$ranger_admin_server/ews/webapp/WEB-INF/classes/ranger-plugins/amazon-emr-emrfs/


#CHECKTHIS - wrong path
sudo cp /usr/lib/ranger/$ranger_admin_server/ews/webapp/WEB-INF/classes/ranger-plugins/hive/* /usr/lib/ranger/$ranger_admin_server/ews/webapp/WEB-INF/lib/ || true

#Setup proper owner for keytabs locations
sudo chown solr:solr -R /etc/solr
sudo chown ranger:ranger -R /etc/ranger

#cleanup
rm -rf ${certs_path}

sudo /usr/bin/ranger-admin stop || true
sudo /usr/bin/ranger-admin start
i=0;
while ! timeout 1 bash -c "echo > /dev/tcp/$current_hostname/6182"; do
        sleep 10;
        i=$((i + 1))
        if (( i > 6 )); then
                break;
        fi
done
#Start Ranger Usersync
sudo /usr/bin/ranger-usersync stop || true
sudo /usr/bin/ranger-usersync start
#cd $installpath

## Update the Ranger service def
installpath=/tmp/ranger-plugins-servicedef/
#Update repo/policies
sudo rm -rf $installpath
sudo mkdir -p $installpath
sudo chmod -R 777 $installpath
cd $installpath
aws s3 cp $s3bucket/${project_version}/inputdata/service-definition/$ranger_service_def_ver/ . --recursive --exclude "*" --include "*.json" --region us-east-1
for i in `find . -name "ranger-servicedef-*.json" -type f`; do
    file_name=`echo "$i" | cut -c 3-`
    echo "$file_name"
    curl -iv --insecure -u admin:admin -X POST -d @$file_name -H "Accept: application/json" -H "Content-Type: application/json" -k $HTTP_URL/service/public/v2/api/servicedef
done

# Restart SOLR
sudo /opt/solr/ranger_audit_server/scripts/stop_solr.sh || true
sudo /opt/solr/ranger_audit_server/scripts/start_solr.sh
#curl -X POST -H 'Content-Type: application/json'  http://localhost:8983/solr/ranger_audits/update?commit=true -d '{ "delete": {"query":"*:*"} }'
