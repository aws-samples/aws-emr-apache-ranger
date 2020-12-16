#!/bin/bash -xe

#CFN_STACK_NAME=$1
#REGION=$2
MASTER_URL=$(curl -s http://169.254.169.254/latest/meta-data/hostname)
sudo yum update -y aws-cfn-bootstrap
/opt/aws/bin/cfn-signal -e $? --id clusterURL --data $MASTER_URL $1

#/opt/aws/bin/cfn-signal -e $? --stack $CFN_STACK_NAME --resource LaunchKerberizedCluster --region $REGION
