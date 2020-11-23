#!/bin/bash
set -euo pipefail
set -x
# Define variables
awsregion=$1
echo "create 'hbase_tblanalyst1', 'analyst1'" | hbase shell -n
echo "create 'hbase_tblanalyst2', 'analyst2'" | hbase shell -n
echo "USE default;
CREATE EXTERNAL TABLE IF NOT EXISTS hbase_tblanalyst1 (
 ad_id STRING,
 request_begin_time STRING,
 impression_id STRING, 
 page STRING,
 user_agent STRING,
 user_cookie STRING,
 ip_address STRING,
 clicked BOOLEAN )
stored by \"org.apache.hadoop.hive.hbase.HBaseStorageHandler\" 
with serdeproperties (\"hbase.columns.mapping\" = \":key,analyst1:request_begin_time,analyst1:impression_id,analyst1:page,analyst1:user_agent,analyst1:user_cookie,analyst1:ip_address,analyst1:clicked\") 
tblproperties (\"hbase.table.name\" = \"hbase_tblanalyst1\");
INSERT OVERWRITE TABLE hbase_tblanalyst1 
SELECT ad_id,request_begin_time,impression_id,page,user_agent,user_cookie,ip_address,clicked FROM tblanalyst1;
CREATE EXTERNAL TABLE IF NOT EXISTS hbase_tblanalyst2 (
 ad_id STRING,
 request_begin_time STRING,
 impression_id STRING, 
 page STRING,
 user_agent STRING,
 user_cookie STRING,
 ip_address STRING,
 clicked BOOLEAN )
Pstored by \"org.apache.hadoop.hive.hbase.HBaseStorageHandler\" 
with serdeproperties (\"hbase.columns.mapping\" = \":key,analyst2:request_begin_time,analyst2:impression_id,analyst2:page,analyst2:user_agent,analyst2:user_cookie,analyst2:ip_address,analyst2:clicked\") 
tblproperties (\"hbase.table.name\" = \"hbase_tblanalyst2\");
INSERT OVERWRITE TABLE hbase_tblanalyst2 
SELECT ad_id,request_begin_time,impression_id,page,user_agent,user_cookie,ip_address,clicked FROM tblanalyst2;
" >> createHbaseTable.hql
hive -f createHbaseTable.hql