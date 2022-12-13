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
#%    arg2                          AWS_REGION (AWS region where you want to install the secrets)
#%    arg3                          ACM_PCA_ARN (ACM PCA ARN)
#                                   refer https://docs.aws.amazon.com/privateca/latest/userguide/creating-managing.html  to set up acm pca

#% EXAMPLES
#%    create-tls-certs.sh ranger_demo us-east-1
#%
#================================================================
#- IMPLEMENTATION
#-    version         create-tls-certs.sh 2.0
#-    author          Varun Bhamidimarri, Stefano Sandonà
#-    license         MIT license
#-
#
#================================================================
#================================================================

[ $# -lt 3 ] && { echo "Usage: $0 AWS_CLI_profile AWS_REGION ACM_PCA_ARN(To setup follow this link: https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-profiles.html)"; exit 1; }

set -euo pipefail
set -x

AWS_PROFILE=$1
AWS_REGION=$2
acm_pca_auth_arn=$3
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
  if [[ $DIR_EXISTS = "false" ]]; then
    rm -rf $1
    mkdir -p $1
    pushd $1
    openssl req -newkey rsa:4096 -keyout privateKey.pem -out certSignRequestforacmpca.csr   -days 365 -nodes -subj ${certs_subject}
    get_certificate_arn=$(aws acm-pca issue-certificate --certificate-authority-arn $acm_pca_auth_arn --csr fileb://certSignRequestforacmpca.csr  --signing-algorithm "SHA256WITHRSA" --validity Value=365,Type="DAYS" --query "CertificateArn" --output=text --profile $AWS_PROFILE --region $AWS_REGION)
    sleep 5
    aws acm-pca get-certificate --certificate-authority-arn $acm_pca_auth_arn --certificate-arn $get_certificate_arn --profile $AWS_PROFILE --region $AWS_REGION --query "Certificate" --output=text > publiccertificate.pem
    aws acm-pca get-certificate --certificate-authority-arn $acm_pca_auth_arn --certificate-arn $get_certificate_arn --profile $AWS_PROFILE --region $AWS_REGION --query "CertificateChain" --output=text > trustedCertificates.pem
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


# Delete existing secrets
aws secretsmanager delete-secret --secret-id emr/rangerGAagentkey --force-delete-without-recovery --profile $AWS_PROFILE --region $AWS_REGION --cli-read-timeout 10 --cli-connect-timeout 10
aws secretsmanager delete-secret --secret-id emr/rangerGAservercert --force-delete-without-recovery --profile $AWS_PROFILE --region $AWS_REGION --cli-read-timeout 10 --cli-connect-timeout 10

## Basic wait for delete to be complete
sleep 30

#Place the agent private key and public certificate for agenet
cat ${ranger_agents_certs_path}/privateKey.pem ${ranger_agents_certs_path}/publiccertificate.pem > ${ranger_agents_certs_path}/rangerGAagentKeyChain.pem

aws secretsmanager create-secret --name emr/rangerGAagentkey \
          --description "X509 Ranger Agent Private Key to be used by EMR Security Config" --secret-string file://${ranger_agents_certs_path}/rangerGAagentKeyChain.pem --profile $AWS_PROFILE --region $AWS_REGION

#Place the  server public certificate for agenet
aws secretsmanager create-secret --name emr/rangerGAservercert \
          --description "Ranger Server Cert" --secret-string file://${ranger_server_certs_path}/publiccertificate.pem --profile $AWS_PROFILE --region $AWS_REGION

## Others that will be used by the Ranger Admin Server
aws secretsmanager delete-secret --secret-id emr/rangerServerPrivateKey --force-delete-without-recovery --profile $AWS_PROFILE --region $AWS_REGION --cli-read-timeout 10 --cli-connect-timeout 10
aws secretsmanager delete-secret --secret-id emr/rangerServerPublicCert --force-delete-without-recovery --profile $AWS_PROFILE --region $AWS_REGION --cli-read-timeout 10 --cli-connect-timeout 10
aws secretsmanager delete-secret --secret-id emr/rangerServerTrustCert --force-delete-without-recovery --profile $AWS_PROFILE --region $AWS_REGION --cli-read-timeout 10 --cli-connect-timeout 10

aws secretsmanager delete-secret --secret-id emr/rangerPluginPrivateKey --force-delete-without-recovery --profile $AWS_PROFILE --region $AWS_REGION --cli-read-timeout 10 --cli-connect-timeout 10
aws secretsmanager delete-secret --secret-id emr/rangerPluginPublicCert --force-delete-without-recovery --profile $AWS_PROFILE --region $AWS_REGION --cli-read-timeout 10 --cli-connect-timeout 10
aws secretsmanager delete-secret --secret-id emr/rangerPluginTrustCert --force-delete-without-recovery --profile $AWS_PROFILE --region $AWS_REGION --cli-read-timeout 10 --cli-connect-timeout 10

aws secretsmanager delete-secret --secret-id emr/rangerSolrPrivateKey --force-delete-without-recovery --profile $AWS_PROFILE --region $AWS_REGION --cli-read-timeout 10 --cli-connect-timeout 10
aws secretsmanager delete-secret --secret-id emr/rangerSolrPublicCert --force-delete-without-recovery --profile $AWS_PROFILE --region $AWS_REGION --cli-read-timeout 10 --cli-connect-timeout 10
aws secretsmanager delete-secret --secret-id emr/rangerSolrTrustCert --force-delete-without-recovery --profile $AWS_PROFILE --region $AWS_REGION --cli-read-timeout 10 --cli-connect-timeout 10

sleep 30

aws secretsmanager create-secret --name emr/rangerServerPrivateKey --description "Ranger Server Private Key" --secret-string file://${ranger_server_certs_path}/privateKey.pem --profile $AWS_PROFILE --region $AWS_REGION
aws secretsmanager create-secret --name emr/rangerServerPublicCert --description "Ranger Server cert chain" --secret-string file://${ranger_server_certs_path}/publiccertificate.pem --profile $AWS_PROFILE --region $AWS_REGION
aws secretsmanager create-secret --name emr/rangerServerTrustCert --description "Ranger Server trust cert" --secret-string file://${ranger_server_certs_path}/trustedCertificates.pem --profile $AWS_PROFILE --region $AWS_REGION

aws secretsmanager create-secret --name emr/rangerPluginPrivateKey --description "Ranger Plugin Private Key" --secret-string file://${ranger_agents_certs_path}/privateKey.pem --profile $AWS_PROFILE --region $AWS_REGION
aws secretsmanager create-secret --name emr/rangerPluginPublicCert --description "Ranger Plugin Cert" --secret-string file://${ranger_agents_certs_path}/publiccertificate.pem --profile $AWS_PROFILE --region $AWS_REGION
aws secretsmanager create-secret --name emr/rangerPluginTrustCert --description "Ranger trust cert" --secret-string file://${ranger_agents_certs_path}/trustedCertificates.pem --profile $AWS_PROFILE --region $AWS_REGION

aws secretsmanager create-secret --name emr/rangerSolrPrivateKey --description "Ranger Solr Private Key" --secret-string file://${solr_certs_path}/privateKey.pem --profile $AWS_PROFILE --region $AWS_REGION
aws secretsmanager create-secret --name emr/rangerSolrPublicCert --description "Ranger Solr Cert" --secret-string file://${solr_certs_path}/publiccertificate.pem --profile $AWS_PROFILE --region $AWS_REGION
aws secretsmanager create-secret --name emr/rangerSolrTrustCert --description "Ranger Solr Cert Chain" --secret-string file://${solr_certs_path}/trustedCertificates.pem --profile $AWS_PROFILE --region $AWS_REGION
