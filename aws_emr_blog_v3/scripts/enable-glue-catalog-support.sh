#!/bin/bash
set -euo pipefail
set -x

new_property_for_glue="<property>\n<name>hive.metastore.client.factory.class</name>\n<value>com.amazonaws.glue.catalog.metastore.AWSGlueDataCatalogHiveClientFactory</value>\n</property>"
record_server_hive_site_file=/etc/emr-record-server/conf/hive-site.xml
record_server_startup_script_file=/etc/emr-record-server/conf/recordserver-env.sh

new_property_for_glue_formatted=$(echo $new_property_for_glue | sed 's/\//\\\//g')

if grep -F "AWSGlueDataCatalogHiveClientFactory" $record_server_hive_site_file
then
    echo "property already exists in file $record_server_hive_site_file"
else
    sudo sed -i "/<\/configuration>/ s/.*/${new_property_for_glue_formatted}\n&/" $record_server_hive_site_file
fi

if grep -F "aws-glue-datacatalog-spark-client" $record_server_startup_script_file
then
    echo "property already exists in file $record_server_startup_script_file"
else
    sudo sed -i 's|"$|:/usr/share/aws/hmclient/lib/aws-glue-datacatalog-spark-client.jar"|' $record_server_startup_script_file
fi

sudo systemctl stop emr-record-server
sudo systemctl start emr-record-server
