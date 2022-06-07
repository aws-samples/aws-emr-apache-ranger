#!/bin/bash
#===============================================================================
#!# script: ba_ranger_glue_catalog_preview.sh
#!# authors: ripani
#!# version: v0.1
#!#
#!# This Bootstrap Action enables the use of the Glue Data Catalog with the EMR
#?# integration with Apache Ranger.
#===============================================================================
#?#
#?# usage: ./ba_ranger_glue_catalog_preview.sh
#?#
#?# Requirements:
#?# - Step 1: Grant IAM Role For Ranger access to call glue apis
#?# - Step 2: Attach the script to the cluster as Bootstrap Action
#?#
#===============================================================================

# Force the script to run as root
if [ $(id -u) != "0" ]
then
    sudo "$0" "$@"
    exit $?
fi

set -x

#===============================================================================
# Requirement
#===============================================================================
wget -O epel.rpm –nv https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
yum install -y ./epel.rpm && yum -y install xmlstarlet

#===============================================================================
# Patch
#===============================================================================
while [[ $(sed '/localInstance {/{:1; /}/!{N; b1}; /nodeProvision/p}; d' /emr/instance-controller/lib/info/job-flow-state.txt | sed '/nodeProvisionCheckinRecord {/{:1; /}/!{N; b1}; /status/p}; d' | awk '/SUCCESSFUL/' | xargs) != "status: SUCCESSFUL" ]];
do
  sleep 1
done

RECORD_SERVER_CONF="/etc/emr-record-server/conf/hive-site.xml"

xmlstarlet ed -L \
-s '//configuration' -t elem -n "property" \
-s '//configuration/property[last()]' -t elem -n "name" -v "hive.metastore.client.factory.class" \
-s '//configuration/property[last()]' -t elem -n "value" -v "com.amazonaws.glue.catalog.metastore.AWSGlueDataCatalogHiveClientFactory" ${RECORD_SERVER_CONF}

# Copy required libraries
cp /usr/share/aws/hmclient/lib/aws-glue-datacatalog-spark-client.jar /usr/share/aws/emr/record-server/lib/jars/

# restart EMR record server component
systemctl stop emr-record-server
systemctl start emr-record-server
