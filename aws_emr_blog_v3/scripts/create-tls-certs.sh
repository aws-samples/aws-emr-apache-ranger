#!/bin/bash
#==============================================================================
#!# create-tls-certs.sh - Script to create SSL private keys/certs and upload to AWS Secretes Manager and S3
#!#
#!#  version         3.0
#!#  author          Varun Bhamidimarri, Stefano Sandonà
#!#  license         MIT license
#!#
#==============================================================================
#?#
#?# usage:    ./create-tls-certs.sh <AWS_REGION> <S3_BUCKET> <S3_PREFIX> <PROJECT_VERSION>
#?# example:  ./create-tls-certs.sh us-east-1 mybucket myfolder1/myfolder2 3.0
#?#
#?#  AWS_REGION                 AWS region where you want to install the secrets eg: us-east-1
#?#  S3_BUCKET                  Amazon S3 bucket where to copy the generated certificates eg: mybucket
#?#  S3_PREFIX                  Amazon S3 bucket prefix where to copy the generated certificates eg: myfolder1/myfolder2
#?#  PROJECT_VERSION            Project version eg: 3.0
#?#
#==============================================================================

function usage() {
	[ "$*" ] && echo "$0: $*"
	sed -n '/^#?#/,/^$/s/^#?# \{0,1\}//p' "$0"
	exit 1
}

[[ $# -ne 4 ]] && echo "error: missing parameters" && usage

set -euo pipefail
set -x

mkdir -p /tmp/emr-tls/
cd /tmp/emr-tls/

sudo yum -y install java-1.8.0
sudo yum -y remove java-1.7.0-openjdk
sudo yum -y install openssl-devel

AWS_REGION=$1
S3_BUCKET=${2-'null'}
S3_KEY=${3-'null'}
CODE_TAG=${4-'null'}

configured_region=$(tr '[:upper:]' '[:lower:]' <<< "$AWS_REGION")
echo "Using region $configured_region"

if [[ $configured_region = "us-east-1" ]]; then
  DEFAULT_EC2_REALM='ec2.internal'
  echo "AWS region is us-east-1, will use EC2 realm as $DEFAULT_EC2_REALM"
else
   DEFAULT_EC2_REALM="$configured_region.compute.internal"
   echo "AWS region is NOT us-east-1, will use EC2 realm as $DEFAULT_EC2_REALM"
fi
ranger_plugin_certs_path="./ranger-agents"
solr_certs_path="./solr-client"
keystore_location="./ranger-plugin-keystore.jks"
keystore_alias=rangerplugin
keystore_password="changeit"
truststore_location="./ranger-plugin-truststore.jks"
ranger_server_certs_path="./ranger-server"
truststore_password="changeit"
truststore_ranger_server_alias="rangeradmin"
secret_mgr_ranger_plugin_private_key="emr/rangerGAagentkey"
secret_mgr_ranger_plugin_cert="emr/rangerPluginCert"
secret_mgr_ranger_admin_private_key="emr/rangerServerPrivateKey"
secret_mgr_ranger_admin_server_cert="emr/rangerGAservercert"
ranger_admin_server_private_key_exists="false"
ranger_admin_server_cert_exists="false"
ranger_plugin_private_key_exists="false"
ranger_plugin_cert_exists="false"
ranger_solr_cert_exists="false"
ranger_solr_key_exists="false"
ranger_solr_trust_store_exists="false"

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
    zip -r -X ../$1.zip certificateChain.pem privateKey.pem trustedCertificates.pem
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
openssl pkcs12 -export -in ${ranger_plugin_certs_path}/certificateChain.pem -inkey ${ranger_plugin_certs_path}/privateKey.pem -chain -CAfile ${ranger_plugin_certs_path}/trustedCertificates.pem -name ${keystore_alias} -out ${ranger_plugin_certs_path}/keystore.p12 -password pass:${keystore_password}
keytool -importkeystore -deststorepass ${keystore_password} -destkeystore ${keystore_location} -srckeystore ${ranger_plugin_certs_path}/keystore.p12 -srcstoretype PKCS12 -srcstorepass ${keystore_password} -noprompt

# Truststore
rm -rf ${truststore_location}
keytool -import -file ${ranger_server_certs_path}/certificateChain.pem -alias ${truststore_ranger_server_alias} -keystore ${truststore_location} -storepass ${truststore_password} -noprompt


# Delete existing secrets
if (aws secretsmanager describe-secret --secret-id ${secret_mgr_ranger_plugin_private_key} --region $AWS_REGION > /dev/null 2>&1); then
  if [[ $(aws secretsmanager describe-secret --secret-id ${secret_mgr_ranger_plugin_private_key} --query "DeletedDate" --region $AWS_REGION) == "null" ]]; then
     echo "${secret_mgr_ranger_plugin_private_key} already exists. Will not delete and recreate"
     ranger_plugin_private_key_exists="true"
  fi
fi
if (aws secretsmanager describe-secret --secret-id ${secret_mgr_ranger_plugin_cert} --region $AWS_REGION > /dev/null 2>&1); then
  if [[ $(aws secretsmanager describe-secret --secret-id ${secret_mgr_ranger_plugin_cert} --query "DeletedDate" --region $AWS_REGION) == "null" ]]; then
     echo "${secret_mgr_ranger_plugin_cert} already exists. Will not delete and recreate"
     ranger_plugin_cert_exists="true"
  fi
fi

if (aws secretsmanager describe-secret --secret-id ${secret_mgr_ranger_admin_private_key} --region $AWS_REGION > /dev/null 2>&1); then
  if [[ $(aws secretsmanager describe-secret --secret-id ${secret_mgr_ranger_admin_private_key} --query "DeletedDate" --region $AWS_REGION) == "null" ]]; then
     echo "${secret_mgr_ranger_admin_private_key} already exists. Will not delete and recreate"
     ranger_admin_server_private_key_exists="true"
  fi
fi

if (aws secretsmanager describe-secret --secret-id ${secret_mgr_ranger_admin_server_cert} --region $AWS_REGION > /dev/null 2>&1); then
  if [[ $(aws secretsmanager describe-secret --secret-id ${secret_mgr_ranger_admin_server_cert} --query "DeletedDate" --region $AWS_REGION) == "null" ]]; then
     echo "${secret_mgr_ranger_admin_server_cert} already exists. Will not delete and recreate"
     ranger_admin_server_cert_exists="true"
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

if [ $ranger_admin_server_private_key_exists == "false" ] && [ $ranger_admin_server_cert_exists == "false" ]; then
  aws secretsmanager delete-secret --secret-id ${secret_mgr_ranger_admin_private_key} --force-delete-without-recovery --region $AWS_REGION --cli-read-timeout 10 --cli-connect-timeout 10
  aws secretsmanager delete-secret --secret-id ${secret_mgr_ranger_admin_server_cert} --force-delete-without-recovery --region $AWS_REGION --cli-read-timeout 10 --cli-connect-timeout 10

  ## Basic wait for delete to be complete
  sleep 60


  aws secretsmanager create-secret --name ${secret_mgr_ranger_admin_private_key} --description "Ranger Server Private Key" --secret-string file://${ranger_server_certs_path}/privateKey.pem --region $AWS_REGION
  aws secretsmanager create-secret --name ${secret_mgr_ranger_admin_server_cert} \
          --description "Ranger Server Cert" --secret-string file://${ranger_server_certs_path}/certificateChain.pem --region $AWS_REGION

  cd /tmp/emr-tls/
  aws s3 cp . s3://${S3_BUCKET}/${S3_KEY}/${CODE_TAG}/emr-tls/ --exclude '*' --include '*.zip' --include '*.jks' --exclude 'emr-certs.zip' --recursive
fi

## Others that will be used by the Ranger Admin Server

if [ $ranger_plugin_private_key_exists == "false" ] && [ $ranger_plugin_cert_exists == "false" ]; then
  aws secretsmanager delete-secret --secret-id ${secret_mgr_ranger_plugin_private_key} --force-delete-without-recovery --region $AWS_REGION --cli-read-timeout 10 --cli-connect-timeout 10
  aws secretsmanager delete-secret --secret-id ${secret_mgr_ranger_plugin_cert} --force-delete-without-recovery --region $AWS_REGION --cli-read-timeout 10 --cli-connect-timeout 10

  sleep 60
  cat ${ranger_plugin_certs_path}/privateKey.pem ${ranger_plugin_certs_path}/certificateChain.pem > ${ranger_plugin_certs_path}/rangerGAagentKeyChain.pem
  aws secretsmanager create-secret --name ${secret_mgr_ranger_plugin_private_key} \
            --description "X509 Ranger Agent Private Key to be used by EMR Security Config" --secret-string file://${ranger_plugin_certs_path}/rangerGAagentKeyChain.pem --region $AWS_REGION
  aws secretsmanager create-secret --name ${secret_mgr_ranger_plugin_cert} --description "Ranger Plugin Cert" --secret-string file://${ranger_plugin_certs_path}/certificateChain.pem --region $AWS_REGION

fi

if [ $ranger_solr_cert_exists == "false" ] && [ $ranger_solr_key_exists == "false" ] && [ $ranger_solr_trust_store_exists == "false" ]; then
  aws secretsmanager delete-secret --secret-id emr/rangerSolrCert --force-delete-without-recovery --region $AWS_REGION --cli-read-timeout 10 --cli-connect-timeout 10
  aws secretsmanager delete-secret --secret-id emr/rangerSolrPrivateKey --force-delete-without-recovery --region $AWS_REGION --cli-read-timeout 10 --cli-connect-timeout 10
  aws secretsmanager delete-secret --secret-id emr/rangerSolrTrustedCert --force-delete-without-recovery --region $AWS_REGION --cli-read-timeout 10 --cli-connect-timeout 10

  sleep 60

  aws secretsmanager create-secret --name emr/rangerSolrCert --description "Ranger Solr Cert" --secret-string file://${solr_certs_path}/trustedCertificates.pem --region $AWS_REGION
  aws secretsmanager create-secret --name emr/rangerSolrPrivateKey --description "Ranger Solr Private Key" --secret-string file://${solr_certs_path}/privateKey.pem --region $AWS_REGION
  aws secretsmanager create-secret --name emr/rangerSolrTrustedCert --description "Ranger Solr Cert Chain" --secret-string file://${solr_certs_path}/certificateChain.pem --region $AWS_REGION
fi

cd /tmp/emr-tls/
aws s3 cp . s3://${S3_BUCKET}/${S3_KEY}/${CODE_TAG}/emr-tls/ --exclude '*' --include 'emr-certs.zip' --recursive
