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
service=hadoop

hostname=`hostname -I | xargs`
ranger_server_fqdn=$hostname
ranger_version=$1
s3bucket=$2
project_version=${3-'2.0'}
http_protocol=${4-'http'}

if [ "$http_protocol" == "https" ]; then
  RANGER_HTTP_URL=https://$ranger_server_fqdn:6182
  SOLR_HTTP_URL=https://$ranger_server_fqdn:8984
else
  RANGER_HTTP_URL=http://$ranger_server_fqdn:6080
  SOLR_HTTP_URL=http://$ranger_server_fqdn:8983
fi

if [ "$ranger_version" == "2.0" ]; then
   ranger_download_version=2.1.0-SNAPSHOT
else
   ranger_download_version=1.0.1
fi


#sudo sed 's/awsemr.com/ec2.internal awsemr.com\nnameserver 10.0.0.2\n/g'

ranger_s3bucket=$s3bucket/ranger/ranger-$ranger_download_version

ranger_tagsync_plugin=ranger-$ranger_download_version-tagsync



## Cert configuration
certs_path="/tmp/certs"
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

if [ ! -f "$ranger_admin_keystore_location" ] || [ ! -f "$ranger_admin_truststore_location" ]; then
  #Download certs
  rm -rf ${certs_path}
  mkdir -p ${certs_path}
  aws s3 sync ${certs_s3_location} ${certs_path}

  mkdir -p ${ranger_agents_certs_path}
  mkdir -p ${ranger_server_certs_path}
  mkdir -p ${solr_certs_path}

  unzip -o ${ranger_agents_certs_path}.zip -d ${ranger_agents_certs_path}
  unzip -o ${ranger_server_certs_path}.zip -d ${ranger_server_certs_path}
  unzip -o ${solr_certs_path}.zip -d ${solr_certs_path}

  sudo mkdir -p /etc/ranger/admin/conf

  #Setup Keystore for RangerAdmin
  openssl pkcs12 -export -in ${ranger_server_certs_path}/certificateChain.pem -inkey ${ranger_server_certs_path}/privateKey.pem -chain -CAfile ${ranger_server_certs_path}/trustedCertificates.pem -name ${ranger_admin_keystore_alias} -out ${ranger_server_certs_path}/keystore.p12 -password pass:${ranger_admin_keystore_password}
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
fi

#Setup
sudo rm -rf $installpath/$ranger_tagsync_plugin
sudo chmod -R 777 $installpath
cd $installpath
aws s3 cp $ranger_s3bucket/$ranger_tagsync_plugin.tar.gz . --region us-east-1
mkdir $ranger_tagsync_plugin
tar -xvf $ranger_tagsync_plugin.tar.gz -C $ranger_tagsync_plugin --strip-components=1
cd $installpath/$ranger_tagsync_plugin

## Updates for new Ranger
#Update Ranger URL in Tag sync conf
sudo sed -i "s|TAG_DEST_RANGER_ENDPOINT =.*|TAG_DEST_RANGER_ENDPOINT =$RANGER_HTTP_URL|g" install.properties
sudo sed -i "s|TAG_SOURCE_ATLAS_ENABLED =.*|TAG_SOURCE_ATLAS_ENABLED =false|g" install.properties
sudo sed -i "s|TAG_SOURCE_FILE_ENABLED =.*|TAG_SOURCE_FILE_ENABLED =true|g" install.properties
sudo sed -i "s|TAG_SOURCE_FILE_FILENAME =.*|TAG_SOURCE_FILE_FILENAME =/etc/ranger/data/tags.json|g" install.properties
sudo sed -i "s|TAG_SOURCE_FILE_CHECK_INTERVAL_IN_MILLIS =.*|TAG_SOURCE_FILE_CHECK_INTERVAL_IN_MILLIS =30000|g" install.properties
sudo sed -i "s|TAG_DEST_RANGER_SSL_CONFIG_FILENAME =.*|TAG_DEST_RANGER_SSL_CONFIG_FILENAME =/etc/ranger/tagsync/conf/ranger-policymgr-ssl.xml|g" install.properties
sudo echo "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"no\"?>
<configuration xmlns:xi=\"http://www.w3.org/2001/XInclude\">
	<property>
		<name>xasecure.policymgr.clientssl.truststore</name>
		<value>/usr/lib/jvm/jre/lib/security/cacerts</value>
		<description>
			java truststore file
		</description>
	</property>
	<property>
		<name>xasecure.policymgr.clientssl.truststore.credential.file</name>
		<value>jceks://file/etc/ranger/tagsync/cred.jceks</value>
		<description>
			java  truststore credential file
		</description>
	</property>
</configuration>" > /etc/ranger/tagsync/conf/ranger-policymgr-ssl.xml
sudo rm -rf /etc/ranger/tagsync/cred.jceks
$JAVA_HOME/bin/java -cp  "/usr/lib/ranger/ranger-2.1.0-SNAPSHOT-admin/cred/lib/*" org.apache.ranger.credentialapi.buildks create "sslTrustStore" -value "changeit" -provider jceks://file/etc/ranger/tagsync/cred.jceks

aws s3 cp $s3bucket/${project_version}/inputdata/tags.json /etc/ranger/data/tags.json

sudo -E bash setup.sh

sudo /usr/bin/ranger-tagsync-services.sh stop || true
sudo /usr/bin/ranger-tagsync-services.sh start

# curl -iv --insecure -u admin:<password>> -H "Content-Type: application/json" -X GET https://<ip-address>:6182/service/tags/tags/
# curl -iv --insecure -u admin:<password> -d @/etc/ranger/data/tags.json -H "Content-Type: application/json" -X PUT https://<ip-address>:6182/service/tags/importservicetags
# curl -iv --insecure -u admin:<password> -H "Content-Type: application/json" -X DELETE https://<ip-address>:6182/service/tags/
