#!/bin/bash
set -euo pipefail
set -x
scripts_repo_path=$1
mkdir -p /tmp/aws-blog-emr-ranger/scripts/emr-steps/
cd /tmp/aws-blog-emr-ranger/scripts/emr-steps/
#sudo yum -y install svn
#svn export $git_repo_path aws-blog-emr-ranger
aws s3 sync $scripts_repo_path/scripts/emr-steps . --region us-east-1
chmod -R 777 /tmp/aws-blog-emr-ranger
