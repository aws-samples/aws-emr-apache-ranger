#!/bin/bash -xe

#================================================================
# Signals the Cloudformation stack that the setup is complete. If this is not run the CFN stack will show as "Failed"
#================================================================
#% SYNOPSIS
#+    send-cf-signal.sh args ...
#%
#% DESCRIPTION
#%    Signals the Cloudformation stack that the setup is complete. If this is not run the CFN stack will show as "Failed"
#%
#% EXAMPLES
#%    send-cf-signal.sh args ..
#%
#================================================================
#- IMPLEMENTATION
#-    version         send-cf-signal.sh 1.0
#-    author          Varun Bhamidimarri
#-    license         MIT license
#-
#
#================================================================
#================================================================

#CFN_STACK_NAME=$1
#REGION=$2
MASTER_URL=$(curl -s http://169.254.169.254/latest/meta-data/hostname)
sudo yum update -y aws-cfn-bootstrap --skip-broken
/opt/aws/bin/cfn-signal -e $? --id clusterURL --data $MASTER_URL $1

#/opt/aws/bin/cfn-signal -e $? --stack $CFN_STACK_NAME --resource LaunchKerberizedCluster --region $REGION
