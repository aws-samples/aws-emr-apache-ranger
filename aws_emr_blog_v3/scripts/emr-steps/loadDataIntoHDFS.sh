#!/bin/bash
set -euo pipefail
set -x
#================================================================
# Creates dummy HDFS data for testing
#================================================================
#% SYNOPSIS
#+    createHiveTables.sh args ...
#%
#% DESCRIPTION
#%    Uses Hadoop commands to create dummy HDFS data for testing
#%
#% EXAMPLES
#%    createHiveTables.sh args ..
#%
#================================================================
#- IMPLEMENTATION
#-    version         createHiveTables.sh 1.0
#-    author          Varun Bhamidimarri
#-    license         MIT license
#-
#
#================================================================
#================================================================

# Define variables
awsregion=$1
installpath=/tmp
hdfs_data_location=s3://$awsregion.elasticmapreduce.samples/freebase/data
cd $installpath
sudo aws s3 cp $hdfs_data_location/football_coach.tsv . --region us-east-1
sudo aws s3 cp $hdfs_data_location/football_coach_position.tsv . --region us-east-1
sudo -u hdfs hadoop fs -mkdir -p /user/analyst1
sudo -u hdfs hadoop fs -mkdir -p /user/analyst2
sudo -u hdfs hadoop fs -put -f football_coach.tsv /user/analyst1
sudo -u hdfs hadoop fs -put -f football_coach_position.tsv /user/analyst2
sudo -u hdfs hadoop fs -chown -R analyst1:analyst1 /user/analyst1
sudo -u hdfs hadoop fs -chown -R analyst2:analyst2 /user/analyst2
