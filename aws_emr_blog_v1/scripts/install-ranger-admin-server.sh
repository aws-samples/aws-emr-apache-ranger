#!/bin/bash
set -euo pipefail
set -x
sudo yum -y install java-1.8.0
sudo yum -y remove java-1.7.0-openjdk
export JAVA_HOME=/usr/lib/jvm/jre
# Define variables
hostname=`hostname -I | xargs`
installpath=/usr/lib/ranger
ranger_version=$5
s3path=$6
project_version=${7-'1.0'}
ldap_admin_password=$8
ldap_bind_password=$9
ldap_default_user_password=${10}
emr_version=${11-'emr-5.30'}

emr_release_version_regex="^emr-6.*"
if [[ ( "$emr_version" =~ $emr_release_version_regex ) ]]; then
  ranger_download_version=2.2.0-SNAPSHOT
elif [ "$ranger_version" == "2.0" ]; then
   ranger_download_version=2.1.0-SNAPSHOT
else
   ranger_download_version=1.1.0
fi

ranger_s3path=$s3path/ranger/ranger-$ranger_download_version
ranger_admin_server=ranger-$ranger_download_version-admin
ranger_user_sync=ranger-$ranger_download_version-usersync

ldap_ip_address=$1
ldap_server_url=ldap://$ldap_ip_address
ldap_base_dn=$2
ldap_bind_user_dn=$3
ldap_bind_password=$4
mysql_jar_location=$s3path/ranger/ranger-$ranger_download_version/mysql-connector-java-5.1.39.jar
mysql_jar=mysql-connector-java-5.1.39.jar
# Setup
yum install -y openldap openldap-clients openldap-servers
# Setup LDAP users
aws s3 cp $s3path/$project_version/inputdata/load-users-new.ldf . --region us-east-1
aws s3 cp $s3path/$project_version/inputdata/modify-users-new.ldf . --region us-east-1
aws s3 cp $s3path/$project_version/scripts/create-users-using-ldap.sh . --region us-east-1
chmod +x create-users-using-ldap.sh
./create-users-using-ldap.sh $ldap_ip_address $ldap_admin_password $ldap_bind_password $ldap_default_user_password || true
#Install mySQL
yum -y install mysql-server
service mysqld start
chkconfig mysqld on
mysqladmin -u root password rangeradmin || true
mysql -u root -prangeradmin -e "CREATE USER 'rangeradmin'@'localhost' IDENTIFIED BY 'rangeradmin';" || true
mysql -u root -prangeradmin -e "create database ranger;" || true
mysql -u root -prangeradmin -e "GRANT ALL PRIVILEGES ON *.* TO 'rangeradmin'@'localhost' IDENTIFIED BY 'rangeradmin'" || true
mysql -u root -prangeradmin -e "FLUSH PRIVILEGES;" || true
rm -rf $installpath
mkdir -p $installpath/hadoop
cd $installpath
aws s3 cp $ranger_s3path/$ranger_admin_server.tar.gz . --region us-east-1
aws s3 cp $ranger_s3path/$ranger_user_sync.tar.gz . --region us-east-1
aws s3 cp $mysql_jar_location . --region us-east-1
aws s3 cp $ranger_s3path/solr_for_audit_setup.tar.gz . --region us-east-1
#Update ranger admin install.properties
tar -xvf $ranger_admin_server.tar.gz
cd $ranger_admin_server
sudo sed -i "s|SQL_CONNECTOR_JAR=.*|SQL_CONNECTOR_JAR=$installpath/$mysql_jar|g" install.properties
sudo sed -i "s|db_root_password=.*|db_root_password=rangeradmin|g" install.properties
sudo sed -i "s|db_password=.*|db_password=rangeradmin|g" install.properties
sudo sed -i "s|audit_db_password=.*|audit_db_password=rangerlogger|g" install.properties
sudo sed -i "s|audit_store=.*|audit_store=solr|g" install.properties
sudo sed -i "s|audit_solr_urls=.*|audit_solr_urls=http://localhost:8983/solr/ranger_audits|g" install.properties
sudo sed -i "s|policymgr_external_url=.*|policymgr_external_url=http://$hostname:6080|g" install.properties
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
chmod +x setup.sh
./setup.sh
#Update ranger usersync install.properties
cd $installpath
mkdir $ranger_user_sync
tar -xvf $ranger_user_sync.tar.gz -C $ranger_user_sync --strip-components=1
cp ./$ranger_admin_server/ews/webapp/WEB-INF/lib/jackson-* ./$ranger_user_sync/lib/
chown ranger:ranger ./$ranger_user_sync/lib/*
chmod 755 ./$ranger_user_sync/lib/*
mkdir -p $installpath/logs/admin/
sudo ln -sf $(pwd)/$ranger_admin_server/ews/logs $installpath/logs/admin || true


cd $ranger_user_sync
sudo sed -i "s|POLICY_MGR_URL =.*|POLICY_MGR_URL=http://$hostname:6080|g" install.properties
sudo sed -i "s|SYNC_SOURCE =.*|SYNC_SOURCE=ldap|g" install.properties
sudo sed -i "s|SYNC_LDAP_URL =.*|SYNC_LDAP_URL=$ldap_server_url|g" install.properties
sudo sed -i "s|SYNC_LDAP_BIND_DN =.*|SYNC_LDAP_BIND_DN=$ldap_bind_user_dn|g" install.properties
sudo sed -i "s|SYNC_LDAP_BIND_PASSWORD =.*|SYNC_LDAP_BIND_PASSWORD=$ldap_bind_password|g" install.properties
sudo sed -i "s|SYNC_LDAP_SEARCH_BASE =.*|SYNC_LDAP_SEARCH_BASE=$ldap_base_dn|g" install.properties
sudo sed -i "s|SYNC_LDAP_USER_SEARCH_BASE =.*|SYNC_LDAP_USER_SEARCH_BASE=cn=users,$ldap_base_dn|g" install.properties
sudo sed -i "s|SYNC_LDAP_USER_SEARCH_FILTER =.*|SYNC_LDAP_USER_SEARCH_FILTER=objectclass=user|g" install.properties
sudo sed -i "s|SYNC_LDAP_USER_NAME_ATTRIBUTE =.*|SYNC_LDAP_USER_NAME_ATTRIBUTE=sAMAccountName|g" install.properties
sudo sed -i "s|SYNC_INTERVAL =.*|SYNC_INTERVAL=2|g" install.properties
chmod +x setup.sh
./setup.sh
#Download the install solr for ranger
cd $installpath
tar -xvf solr_for_audit_setup.tar.gz
cd solr_for_audit_setup
sudo sed -i "s|SOLR_HOST_URL=.*|SOLR_HOST_URL=http://$hostname:8983|g" install.properties
sudo sed -i "s|SOLR_RANGER_PORT=.*|SOLR_RANGER_PORT=8983|g" install.properties
chmod +x setup.sh
./setup.sh
#Start Ranger Admin
sudo /usr/bin/ranger-admin stop || true
sudo /usr/bin/ranger-admin start
i=0;
while ! timeout 1 bash -c "echo > /dev/tcp/$hostname/6080"; do
        sleep 10;
        i=$((i + 1))
        if (( i > 6 )); then
                break;
        fi
done
#Start Ranger Usersync
/usr/bin/ranger-usersync stop || true
/usr/bin/ranger-usersync start
# The default usersync runs every 1 hour (cannot be changed). This is way to force usersync
#sudo echo /usr/bin/ranger-usersync restart | at now + 5 minutes
#sudo echo /usr/bin/ranger-usersync restart | at now + 7 minutes
#sudo echo /usr/bin/ranger-usersync restart | at now + 10 minutes
#Start SOLR
#/opt/solr/bin/solr stop -p 8983 || true
#/opt/solr/bin/solr start
sudo /opt/solr/ranger_audit_server/scripts/stop_solr.sh || true
sudo /opt/solr/ranger_audit_server/scripts/start_solr.sh
