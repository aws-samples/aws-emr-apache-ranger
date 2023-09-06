#!/bin/bash
set -euo pipefail
set -x
#================================================================
# Creates dummy Hive Tables for testing
#================================================================
#% SYNOPSIS
#+    createHiveTables.sh args ...
#%
#% DESCRIPTION
#%    Uses Hive CLI to setup dummy Hive tables
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

#hardcoded as not every region had this dataset
awsregion="us-east-1"
hive_script_data_location=s3://$awsregion.elasticmapreduce.samples/hive-ads/data/
echo "USE default;
CREATE EXTERNAL TABLE IF NOT EXISTS tblanalyst1 (
 request_begin_time STRING,
 ad_id STRING,
 impression_id STRING, 
 page STRING,
 user_agent STRING,
 user_cookie STRING,
 ip_address STRING,
 clicked BOOLEAN )
PARTITIONED BY (
 day STRING,
 hour STRING )
STORED AS SEQUENCEFILE
LOCATION '$hive_script_data_location/joined_impressions/';
MSCK REPAIR TABLE tblanalyst1;
CREATE EXTERNAL TABLE IF NOT EXISTS tblanalyst2 (
 request_begin_time STRING,
 ad_id STRING,
 impression_id STRING, 
 page STRING,
 user_agent STRING,
 user_cookie STRING,
 ip_address STRING,
 clicked BOOLEAN )
PARTITIONED BY (
 day STRING,
 hour STRING )
STORED AS SEQUENCEFILE
LOCATION '$hive_script_data_location/joined_impressions/';
MSCK REPAIR TABLE tblanalyst2;
CREATE EXTERNAL TABLE IF NOT EXISTS impressions (
  requestBeginTime string, adId string, impressionId string, referrer string,
  userAgent string, userCookie string, ip string
)
PARTITIONED BY (dt string)
 ROW FORMAT
 serde 'org.apache.hive.hcatalog.data.JsonSerDe'
 with serdeproperties ( 'paths'='requestBeginTime, adId, impressionId, referrer, userAgent, userCookie, ip' )
LOCATION '$hive_script_data_location/impressions/';
MSCK REPAIR TABLE impressions;
CREATE EXTERNAL TABLE IF NOT EXISTS clicks (
    impressionId string
  )
  partitioned by (dt string)
  row format
    serde 'org.apache.hive.hcatalog.data.JsonSerDe'
    with serdeproperties ( 'paths'='impressionId' )
location '$hive_script_data_location/clicks/' ;
MSCK REPAIR TABLE clicks;
CREATE TABLE IF NOT EXISTS user_mapping (
 user_name STRING,
 page STRING)
STORED AS PARQUET
LOCATION 's3://aws-bigdata-blog/artifacts/aws-blog-emr-ranger/data/user_mapping/';
" >> createTable.hql
sudo -u hive hive -f createTable.hql
