#!/bin/bash
set -euo pipefail
set -x
# Define variables
awsregion=$1
cd /tmp/
echo "
CREATE DATABASE IF NOT EXISTS staging
  COMMENT 'Databse to hold the staging data for retail schema'
  WITH DBPROPERTIES ('creator'='AWS', 'Dept.'='EMR Ranger team');

CREATE DATABASE IF NOT EXISTS processed
  COMMENT 'Databse to hold the processed data for retail schema'
  WITH DBPROPERTIES ('creator'='AWS', 'Dept.'='EMR Ranger team');

CREATE EXTERNAL TABLE IF NOT EXISTS staging.orders (
customer_id string COMMENT 'from deserializer',
order_date string COMMENT 'from deserializer',
price double COMMENT 'from deserializer',
sku string COMMENT 'from deserializer')
STORED AS PARQUET
LOCATION 's3://aws-bigdata-blog/artifacts/aws-blog-emr-ranger/data/staging/orders/';

MSCK REPAIR TABLE staging.orders;


CREATE EXTERNAL TABLE IF NOT EXISTS staging.customers (
cbgid bigint COMMENT 'from deserializer',
customer_id string COMMENT 'from deserializer',
education_level string COMMENT 'from deserializer',
first_name string COMMENT 'from deserializer',
last_name string COMMENT 'from deserializer',
marital_status string COMMENT 'from deserializer',
region string COMMENT 'from deserializer',
state string COMMENT 'from deserializer')
STORED AS PARQUET
LOCATION 's3://aws-bigdata-blog/artifacts/aws-blog-emr-ranger/data/staging/customers/';

MSCK REPAIR TABLE staging.customers;


CREATE EXTERNAL TABLE IF NOT EXISTS staging.products (
company string COMMENT 'from deserializer',
link string COMMENT 'from deserializer',
price double COMMENT 'from deserializer',
product_category string COMMENT 'from deserializer',
release_date string COMMENT 'from deserializer',
sku string COMMENT 'from deserializer')
STORED AS PARQUET
LOCATION 's3://aws-bigdata-blog/artifacts/aws-blog-emr-ranger/data/staging/products/';

MSCK REPAIR TABLE staging.products;

" > createdExtendedHiveTables.hql
sudo -u hive hive -f /tmp/createdExtendedHiveTables.hql

#CREATE EXTERNAL TABLE IF NOT EXISTS staging.demographics (
#bachelors_degrees int COMMENT 'from deserializer',
#children_under_5 int COMMENT 'from deserializer',
#families_with_children int COMMENT 'from deserializer',
#geoid bigint COMMENT 'from deserializer',
#household_income double COMMENT 'from deserializer',
#households int COMMENT 'from deserializer',
#marriedcouple_family int COMMENT 'from deserializer',
#middle_aged_people int COMMENT 'from deserializer',
#owner_occupied int COMMENT 'from deserializer',
#population int COMMENT 'from deserializer',
#population_density double COMMENT 'from deserializer',
#state string COMMENT 'from deserializer')
#STORED AS PARQUET
#LOCATION 's3://aws-bigdata-blog/artifacts/aws-blog-emr-ranger/data/staging/demographics/';
#
#MSCK REPAIR TABLE staging.demographics;
