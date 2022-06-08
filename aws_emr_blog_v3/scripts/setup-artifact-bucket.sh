#!/bin/bash
#==============================================================================
#!# setup-artifact-bucket.sh - Script to setup a regional version of the EMR Ranger
#!# automation. This is required if you need to run the setup outside us-east-1
#!#
#!#  version         1.1
#!#  author          Ripani Lorenzo
#!#  license         MIT license
#!#
#==============================================================================
#?#
#?# usage: ./setup-artifact-bucket.sh <REGIONAL_S3_BUCKET>
#?#        ./setup-artifact-bucket.sh ranger-demo-us-west-2
#?#
#?#  REGIONAL_S3_BUCKET            S3 bucket name eg: ranger-demo-us-west-2
#?#
#==============================================================================
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

function usage() {
  [ "$*" ] && echo "$0: $*"
  sed -n '/^#?#/,/^$/s/^#?# \{0,1\}//p' "$0"
  exit -1
}

[[ $# -ne 1 ]] && echo "error: missing parameters" && usage

REGIONAL_S3_BUCKET="$1"
SOURCE_BUCKET="aws-bigdata-blog/artifacts/aws-blog-emr-ranger"

# Amazon EMR Lambda code
zip -j $DIR/../launch-cluster.zip $DIR/../code/launch-cluster/*.py

# Create repository structure
aws s3 cp $DIR/../launch-cluster.zip s3://${REGIONAL_S3_BUCKET}/artifacts/aws-blog-emr-ranger/3.0/launch-cluster.zip
aws s3 sync $DIR/../cloudformation/ s3://${REGIONAL_S3_BUCKET}/artifacts/aws-blog-emr-ranger/3.0/cloudformation/
aws s3 sync $DIR/../inputdata/ s3://${REGIONAL_S3_BUCKET}/artifacts/aws-blog-emr-ranger/3.0/inputdata/
aws s3 sync $DIR/../scripts/ s3://${REGIONAL_S3_BUCKET}/artifacts/aws-blog-emr-ranger/3.0/scripts/ --exclude '*emr-tls*'

# Copy Apache Ranger 2.x Builds
aws s3 sync s3://aws-bigdata-blog/artifacts/aws-blog-emr-ranger/ranger/ s3://${REGIONAL_S3_BUCKET}/artifacts/aws-blog-emr-ranger/ranger/ --exclude '*' --include '*ranger-2.*'
