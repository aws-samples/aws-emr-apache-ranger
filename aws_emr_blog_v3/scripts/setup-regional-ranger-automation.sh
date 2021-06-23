#!/bin/bash

#================================================================
# Script to setup a regional version of the EMR Ranger automation - This is required if you need to run the setup outside us-east-1
#================================================================
#% SYNOPSIS
#+    setup-regional-ranger-automation.sh args ...
#%
#% DESCRIPTION
#%    Sets up the required
#%
#% ARGUMENTS
#%    arg1                          Pass the AWS profile to use -
#                                   You can configure this using the documentation below
#                                   https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-profiles.html
#     arg2                          AWS_REGION - eg: us-west-2
#     arg3                          REGIONAL_S3_BUCKET - S3 bucket name eg: ranger-demo-us-west-2
#% EXAMPLES
#%    setup-regional-ranger-automation.sh ranger_demo us-west2 ranger-demo-us-west-2
#%
#================================================================
#- IMPLEMENTATION
#-    version         setup-regional-ranger-automation.sh 1.0
#-    author          Varun Bhamidimarri
#-    license         MIT license
#-
#
#================================================================
#================================================================

[ $# -eq 0 ] && { echo "Usage: $0 AWS_CLI_profile aws_region_code regional_s3_bucket_name (To setup follow this link: https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-profiles.html) (eg: ranger_demo us-west2 ranger-demo-us-west-2, ranger_demo eu-north-1 ranger-demo-eu-north-1)"; exit 1; }

set -euo pipefail
set -x

AWS_PROFILE=$1
AWS_REGION=$2
REGIONAL_S3_BUCKET=$3

aws s3 cp s3://aws-bigdata-blog/artifacts/aws-blog-emr-ranger/3.0/amilookup-win.zip s3://${REGIONAL_S3_BUCKET}/artifacts/aws-blog-emr-ranger/3.0/amilookup-win.zip --region ${AWS_REGION} --profile ${AWS_PROFILE}
aws s3 cp s3://aws-bigdata-blog/artifacts/aws-blog-emr-ranger/3.0/launch-cluster.zip s3://${REGIONAL_S3_BUCKET}/artifacts/aws-blog-emr-ranger/3.0/launch-cluster.zip --region ${AWS_REGION} --profile ${AWS_PROFILE}
aws s3 cp s3://aws-bigdata-blog/artifacts/aws-blog-emr-ranger/3.0/scripts/download-scripts.sh s3://${REGIONAL_S3_BUCKET}/artifacts/aws-blog-emr-ranger/3.0/scripts/download-scripts.sh --region ${AWS_REGION} --profile ${AWS_PROFILE}
