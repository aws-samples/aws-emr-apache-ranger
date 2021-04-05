#!/bin/bash

#================================================================
# Script to create SSL private keys/certs and upload to AWS Secretes Manager
#================================================================
#% SYNOPSIS
#+    create-tls-certs.sh args ...
#%
#% DESCRIPTION
#%    Uses openssl to create self-signed keys/certs and uploads to AWS Secretes Manager to
#%    be used for Ranger Admin server and EMR security configuration
#%    Requirements: openssl, aws cli with profile (profile should have IAM permissions to create and delete AWS secrets)
#%
#% ARGUMENTS
#%    arg1                          Pass the AWS profile to use -
#                                   You can configure this using the documentation below
#                                   https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-profiles.html

#% EXAMPLES
#%    create-tls-certs.sh ranger_demo
#%
#================================================================
#- IMPLEMENTATION
#-    version         create-tls-certs.sh 1.0
#-    author          Varun Bhamidimarri, Stefano Sandonà
#-    license         MIT license
#-
#
#================================================================
#================================================================

[ $# -eq 0 ] && { echo "Usage: $0 AWS_CLI_profile (To setup follow this link: https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-profiles.html)"; exit 1; }

set -euo pipefail
set -x

AWS_PROFILE=$1
#AWS_PROFILE=account4
ranger_agents_certs_path="./ranger-agents"
solr_certs_path="./solr-client"
keystore_location="./ranger-plugin-keystore.jks"
keystore_alias=rangerplugin
keystore_password="changeit"
truststore_location="./ranger-plugin-truststore.jks"
ranger_server_certs_path="./ranger-server"
truststore_password="changeit"
truststore_ranger_server_alias="rangeradmin"
secret_mgr_ranger_private_key="emr/rangerGAagentkey"
secret_mgr_ranger_admin_cert="emr/rangerGAservercert"


certs_subject="/C=US/ST=TX/L=Dallas/O=EMR/OU=EMR/CN=*.ec2.internal"

generate_certs() {
  rm -rf $1
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
keytool -importkeystore -deststorepass ${keystore_password} -destkeystore ${keystore_location} -srckeystore ${ranger_agents_certs_path}/keystore.p12 -srcstoretype PKCS12 -srcstorepass ${keystore_password} -noprompt

# Truststore
rm -rf ${truststore_location}
keytool -import -file ${ranger_server_certs_path}/certificateChain.pem -alias ${truststore_ranger_server_alias} -keystore ${truststore_location} -storepass ${truststore_password} -noprompt

# Delete existing secrets
aws secretsmanager delete-secret --secret-id ${secret_mgr_ranger_private_key} --force-delete-without-recovery --profile $AWS_PROFILE --cli-read-timeout 10 --cli-connect-timeout 10
aws secretsmanager delete-secret --secret-id ${secret_mgr_ranger_admin_cert} --force-delete-without-recovery --profile $AWS_PROFILE --cli-read-timeout 10 --cli-connect-timeout 10

## Basic wait for delete to be complete
sleep 30

cat ${ranger_agents_certs_path}/privateKey.pem ${ranger_agents_certs_path}/certificateChain.pem > ${ranger_agents_certs_path}/rangerGAagentKeyChain.pem

aws secretsmanager create-secret --name ${secret_mgr_ranger_private_key} \
          --description "X509 Ranger Agent Private Key to be used by EMR Security Config" --secret-string file://${ranger_agents_certs_path}/rangerGAagentKeyChain.pem --profile $AWS_PROFILE


aws secretsmanager create-secret --name ${secret_mgr_ranger_admin_cert} \
          --description "Ranger Server Cert" --secret-string file://${ranger_server_certs_path}/certificateChain.pem --profile $AWS_PROFILE


## Others that will be used by the Ranger Admin Server

aws secretsmanager delete-secret --secret-id emr/rangerServerPrivateKey --force-delete-without-recovery --profile $AWS_PROFILE --cli-read-timeout 10 --cli-connect-timeout 10
aws secretsmanager delete-secret --secret-id emr/rangerPluginCert --force-delete-without-recovery --profile $AWS_PROFILE --cli-read-timeout 10 --cli-connect-timeout 10
aws secretsmanager delete-secret --secret-id emr/rangerSolrCert --force-delete-without-recovery --profile $AWS_PROFILE --cli-read-timeout 10 --cli-connect-timeout 10
aws secretsmanager delete-secret --secret-id emr/rangerSolrPrivateKey --force-delete-without-recovery --profile $AWS_PROFILE --cli-read-timeout 10 --cli-connect-timeout 10
aws secretsmanager delete-secret --secret-id emr/rangerSolrTrustedCert --force-delete-without-recovery --profile $AWS_PROFILE --cli-read-timeout 10 --cli-connect-timeout 10

sleep 30
aws secretsmanager create-secret --name emr/rangerServerPrivateKey --description "Ranger Server Private Key" --secret-string file://${ranger_server_certs_path}/privateKey.pem --profile $AWS_PROFILE
aws secretsmanager create-secret --name emr/rangerPluginCert --description "Ranger Plugin Cert" --secret-string file://${ranger_agents_certs_path}/certificateChain.pem --profile $AWS_PROFILE
aws secretsmanager create-secret --name emr/rangerSolrCert --description "Ranger Solr Cert" --secret-string file://${solr_certs_path}/trustedCertificates.pem --profile $AWS_PROFILE
aws secretsmanager create-secret --name emr/rangerSolrPrivateKey --description "Ranger Solr Private Key" --secret-string file://${solr_certs_path}/privateKey.pem --profile $AWS_PROFILE
aws secretsmanager create-secret --name emr/rangerSolrTrustedCert --description "Ranger Solr Cert Chain" --secret-string file://${solr_certs_path}/certificateChain.pem --profile $AWS_PROFILE
