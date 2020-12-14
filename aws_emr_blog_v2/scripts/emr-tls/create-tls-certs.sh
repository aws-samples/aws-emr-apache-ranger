#!/bin/bash
set -euo pipefail
set -x

ranger_agents_certs_path="./ranger-agents"
keystore_location="./ranger-plugin-keystore.jks"
keystore_alias=rangerplugin
keystore_password="changeit"
truststore_location="./ranger-plugin-truststore.jks"
ranger_server_certs_path="./ranger-server"
truststore_password="changeit"
truststore_ranger_server_alias="rangeradmin"

certs_subject="/C=US/ST=TX/L=Dallas/O=EMR/OU=EMR/CN=*.ec2.internal"

generate_certs() {
  rm -r $1
  mkdir -p $1
  pushd $1
  openssl req -x509 -newkey rsa:4096 -keyout privateKey.pem -out certificateChain.pem -days 365 -nodes -subj ${certs_subject}
  cp certificateChain.pem trustedCertificates.pem
  zip -r -X ../$1-certs.zip certificateChain.pem privateKey.pem trustedCertificates.pem
#  rm -rf *.pem
  popd
}
rm -rf ${keystore_location}
rm -rf ${truststore_location}
rm -rf ${keystore_location}
generate_certs ranger-server
generate_certs ranger-agents
generate_certs solr-client
generate_certs emr-certs


# Generate KeyStore and TrustStore for the Ranger plugins
# Keystore
openssl pkcs12 -export -in ${ranger_agents_certs_path}/certificateChain.pem -inkey ${ranger_agents_certs_path}/privateKey.pem -chain -CAfile ${ranger_agents_certs_path}/trustedCertificates.pem -name ${keystore_alias} -out ${ranger_agents_certs_path}/keystore.p12 -password pass:${keystore_password}
keytool -importkeystore -deststorepass ${keystore_password} -destkeystore ${keystore_location} -srckeystore ${ranger_agents_certs_path}/keystore.p12 -srcstoretype PKCS12 -srcstorepass ${keystore_password}
# Truststore
keytool -import -file ${ranger_server_certs_path}/certificateChain.pem -alias ${truststore_ranger_server_alias} -keystore ${truststore_location} -storepass ${truststore_password} -noprompt

#aws secretsmanager delete-secret --secret-id emr/rangeragentkey --force-delete-without-recovery --profile account5
#aws secretsmanager delete-secret --secret-id emr/rangerservercert --force-delete-without-recovery --profile account5
#
#sleep 15
#aws secretsmanager create-secret --name emr/rangeragentkey \
#          --description "Ranger Agent Cert" --secret-string file://${ranger_agents_certs_path}/privateKey.pem --profile account5
#
#aws secretsmanager create-secret --name emr/rangerservercert \
#          --description "Ranger Server Cert" --secret-string file://${ranger_server_certs_path}/trustedCertificates.pem --profile account5
