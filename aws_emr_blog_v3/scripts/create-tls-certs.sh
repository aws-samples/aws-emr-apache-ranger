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
#%
#% ARGUMENTS
#%    arg1                          AWS_REGION (AWS region where you want to install the secrets)
#%    arg2                          Copy certs to the local S3 bucket
#%    arg3                          (Optional) Local S3 Bucket to copy certs
#%    arg4                          (Optional) Project version

#% EXAMPLES
#%    create-tls-certs.sh us-east-1 true <s3-bucket> <project-version>
#%
#================================================================
#- IMPLEMENTATION
#-    version         create-tls-certs.sh 2.0
#-    author          Varun Bhamidimarri
#-    license         MIT license
#-
#
#================================================================
#================================================================

[ $# -lt 2 ] && { echo "Usage: $0 AWS_REGION flag_to_copy_artifacts_to_local_s3"; exit 1; }

set -euo pipefail
set -x

mkdir -p /tmp/emr-tls/
cd /tmp/emr-tls/

sudo yum -y install java-1.8.0
sudo yum -y remove java-1.7.0-openjdk
sudo yum -y install openssl-devel

AWS_REGION=$1
COPY_CERT_TO_LOCAL_S3_BUCKET=${2-'false'}
S3_BUCKET=${3-'null'}
S3_KEY=${4-'null'}
CODE_TAG=${5-'null'}

echo $(tr '[:upper:]' '[:lower:]' <<< "$AWS_REGION")
if [[ $(tr '[:upper:]' '[:lower:]' <<< "$AWS_REGION") = "us-east-1" ]]; then
  DEFAULT_EC2_REALM='ec2.internal'
  echo "AWS region is us-east-1, will use EC2 realm as ec2.internal"
else
   DEFAULT_EC2_REALM='compute.internal'
   echo "AWS region is NOT us-east-1, will use EC2 realm as compute.internal"
fi
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

certs_subject="/C=US/ST=TX/L=Dallas/O=EMR/OU=EMR/CN=*.$DEFAULT_EC2_REALM"

generate_certs() {
  DIR_EXISTS="false"
  if [ -d "$1" ]; then
    echo "$1 directory exists, will not recreate certs"
    DIR_EXISTS="true"
  fi
#  rm -rf $1
  if [[ $DIR_EXISTS == "false" ]]; then
    rm -rf $1
    mkdir -p $1
    pushd $1
    openssl req -x509 -newkey rsa:4096 -keyout privateKey.pem -out certificateChain.pem -days 1095 -nodes -subj ${certs_subject}
    cp certificateChain.pem trustedCertificates.pem
    zip -r -X ../$1-certs.zip certificateChain.pem privateKey.pem trustedCertificates.pem
    #  rm -rf *.pem
    popd
  fi
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

ranger_private_key_exists="false"
ranger_admin_cert_exists="false"
ranger_plugin_cert_exists="false"
ranger_solr_cert_exists="false"
ranger_server_key_exists="false"
ranger_solr_key_exists="false"
ranger_solr_trust_store_exists="false"

# Delete existing secrets
if (aws secretsmanager describe-secret --secret-id ${secret_mgr_ranger_private_key} --region $AWS_REGION > /dev/null 2>&1); then
  if [[ $(aws secretsmanager describe-secret --secret-id ${secret_mgr_ranger_private_key} --query "DeletedDate" --region $AWS_REGION) == "null" ]]; then
     echo "${secret_mgr_ranger_private_key} already exists. Will not delete and recreate"
     ranger_private_key_exists="true"
  fi
fi

if (aws secretsmanager describe-secret --secret-id ${secret_mgr_ranger_admin_cert} --region $AWS_REGION > /dev/null 2>&1); then
  if [[ $(aws secretsmanager describe-secret --secret-id ${secret_mgr_ranger_admin_cert} --query "DeletedDate" --region $AWS_REGION) == "null" ]]; then
     echo "${secret_mgr_ranger_admin_cert} already exists. Will not delete and recreate"
     ranger_admin_cert_exists="true"
  fi
fi
if (aws secretsmanager describe-secret --secret-id emr/rangerServerPrivateKey --region $AWS_REGION > /dev/null 2>&1); then
  if [[ $(aws secretsmanager describe-secret --secret-id emr/rangerServerPrivateKey --query "DeletedDate" --region $AWS_REGION) == "null" ]]; then
     echo "emr/rangerServerPrivateKey already exists. Will not delete and recreate"
     ranger_server_key_exists="true"
  fi
fi
if (aws secretsmanager describe-secret --secret-id emr/rangerPluginCert --region $AWS_REGION > /dev/null 2>&1); then
  if [[ $(aws secretsmanager describe-secret --secret-id emr/rangerPluginCert --query "DeletedDate" --region $AWS_REGION) == "null" ]]; then
    echo "emr/rangerPluginCert already exists. Will not delete and recreate"
    ranger_plugin_cert_exists="true"
  fi
fi
if (aws secretsmanager describe-secret --secret-id emr/rangerSolrCert --region $AWS_REGION > /dev/null 2>&1); then
  if [[ $(aws secretsmanager describe-secret --secret-id emr/rangerSolrCert --query "DeletedDate" --region $AWS_REGION) == "null" ]]; then
     echo "emr/rangerSolrCert already exists. Will not delete and recreate"
     ranger_solr_cert_exists="true"
  fi
fi
if (aws secretsmanager describe-secret --secret-id emr/rangerSolrPrivateKey --region $AWS_REGION > /dev/null 2>&1); then
  if [[ $(aws secretsmanager describe-secret --secret-id emr/rangerSolrPrivateKey --query "DeletedDate" --region $AWS_REGION) == "null" ]]; then
     echo "emr/rangerSolrPrivateKey already exists. Will not delete and recreate"
     ranger_solr_key_exists="true"
  fi
fi
if (aws secretsmanager describe-secret --secret-id emr/rangerSolrTrustedCert --region $AWS_REGION > /dev/null 2>&1); then
  if [[ $(aws secretsmanager describe-secret --secret-id emr/rangerSolrTrustedCert --query "DeletedDate" --region $AWS_REGION) == "null" ]]; then
    echo "emr/rangerSolrTrustedCert already exists. Will not delete and recreate"
    ranger_solr_trust_store_exists="true"
  fi
fi

if [ $ranger_private_key_exists == "false" ] && [ $ranger_admin_cert_exists == "false" ]; then
  aws secretsmanager delete-secret --secret-id ${secret_mgr_ranger_private_key} --force-delete-without-recovery --region $AWS_REGION --cli-read-timeout 10 --cli-connect-timeout 10
  aws secretsmanager delete-secret --secret-id ${secret_mgr_ranger_admin_cert} --force-delete-without-recovery --region $AWS_REGION --cli-read-timeout 10 --cli-connect-timeout 10

  ## Basic wait for delete to be complete
  sleep 30

  cat ${ranger_agents_certs_path}/privateKey.pem ${ranger_agents_certs_path}/certificateChain.pem > ${ranger_agents_certs_path}/rangerGAagentKeyChain.pem

  aws secretsmanager create-secret --name ${secret_mgr_ranger_private_key} \
            --description "X509 Ranger Agent Private Key to be used by EMR Security Config" --secret-string file://${ranger_agents_certs_path}/rangerGAagentKeyChain.pem --region $AWS_REGION
  aws secretsmanager create-secret --name ${secret_mgr_ranger_admin_cert} \
          --description "Ranger Server Cert" --secret-string file://${ranger_server_certs_path}/certificateChain.pem --region $AWS_REGION
fi

## Others that will be used by the Ranger Admin Server

if [ $ranger_server_key_exists == "false" ] && [ $ranger_plugin_cert_exists == "false" ] && [ $ranger_solr_cert_exists == "false" ]; then
  aws secretsmanager delete-secret --secret-id emr/rangerServerPrivateKey --force-delete-without-recovery --region $AWS_REGION --cli-read-timeout 10 --cli-connect-timeout 10
  aws secretsmanager delete-secret --secret-id emr/rangerPluginCert --force-delete-without-recovery --region $AWS_REGION --cli-read-timeout 10 --cli-connect-timeout 10
  aws secretsmanager delete-secret --secret-id emr/rangerSolrCert --force-delete-without-recovery --region $AWS_REGION --cli-read-timeout 10 --cli-connect-timeout 10
  aws secretsmanager delete-secret --secret-id emr/rangerSolrPrivateKey --force-delete-without-recovery --region $AWS_REGION --cli-read-timeout 10 --cli-connect-timeout 10
  aws secretsmanager delete-secret --secret-id emr/rangerSolrTrustedCert --force-delete-without-recovery --region $AWS_REGION --cli-read-timeout 10 --cli-connect-timeout 10

  sleep 30
  aws secretsmanager create-secret --name emr/rangerServerPrivateKey --description "Ranger Server Private Key" --secret-string file://${ranger_server_certs_path}/privateKey.pem --region $AWS_REGION
  aws secretsmanager create-secret --name emr/rangerPluginCert --description "Ranger Plugin Cert" --secret-string file://${ranger_agents_certs_path}/certificateChain.pem --region $AWS_REGION
  aws secretsmanager create-secret --name emr/rangerSolrCert --description "Ranger Solr Cert" --secret-string file://${solr_certs_path}/trustedCertificates.pem --region $AWS_REGION
  aws secretsmanager create-secret --name emr/rangerSolrPrivateKey --description "Ranger Solr Private Key" --secret-string file://${solr_certs_path}/privateKey.pem --region $AWS_REGION
  aws secretsmanager create-secret --name emr/rangerSolrTrustedCert --description "Ranger Solr Cert Chain" --secret-string file://${solr_certs_path}/certificateChain.pem --region $AWS_REGION

  if [[ $COPY_CERT_TO_LOCAL_S3_BUCKET == "true" ]]; then
    cd /tmp/emr-tls/
    aws s3 cp . s3://${S3_BUCKET}/${S3_KEY}/${CODE_TAG}/emr-tls/ --exclude '*' --include '*.zip' --include '*.jks' --recursive
  fi
fi
