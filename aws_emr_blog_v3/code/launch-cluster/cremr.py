import boto3
import crhelper

"""Helper class to create EMR cluster.
   Uses various parameters to setup the right EMR configuration

__author__    = "Varun Bhamidimarri"
__license__   = "MIT license"

"""
# initialise logger
logger = crhelper.log_config({"RequestId": "CONTAINER_INIT"})
logger.info("Logging configured")
# set global to track init failures
init_failed = False

try:
    # Place initialization code here
    logger.info("Container initialization completed")
except Exception as e:
    logger.error(e, exc_info=True)
    init_failed = e


def create(event, context):
    apps = event["ResourceProperties"]["AppsEMR"]
    emrReleaseLabel = event["ResourceProperties"]["emrReleaseLabel"]
    prestoEngineRequested = "Presto"
    isPrestoAppRequested = False
    isSparkAppRequested = False
    formatted_applist = apps.split(",")
    applist = []
    for app in formatted_applist:
        applist.append({"Name": app.strip()})
        if app.strip() in ["Presto", "PrestoSQL"]:
            isPrestoAppRequested = True
            prestoEngineRequested = app.strip()
        if app.strip() in ["Spark"]:
            isSparkAppRequested = True

    try:
        emrVersion = emrReleaseLabel.split("-")[1].split(".")
        client = boto3.client(
            "emr", region_name=event["ResourceProperties"]["StackRegion"])
        scriptRunnerJar = "s3://" + event["ResourceProperties"]["StackRegion"] + \
            ".elasticmapreduce/libs/script-runner/script-runner.jar"
        cluster_name = "EMR-" + event["ResourceProperties"]["StackName"]
        cluster_parameters = {
            'Name': cluster_name, 'ReleaseLabel': emrReleaseLabel,
            'LogUri': event["ResourceProperties"]["LogFolder"],
            'AdditionalInfo': '{"clusterType":"development"}',
            'BootstrapActions': [
                {
                    "Name": "Download scripts",
                    "ScriptBootstrapAction": {
                        "Path": "s3://" + event["ResourceProperties"]["S3Bucket"] + "/" + event["ResourceProperties"][
                            "S3Key"] + "/" + event["ResourceProperties"][
                            "ProjectVersion"] + "/scripts/download-scripts.sh",
                        "Args": [
                            "s3://" + event["ResourceProperties"]["S3ArtifactBucket"] + "/" + event["ResourceProperties"][
                                "S3ArtifactKey"] + "/" + event["ResourceProperties"][
                                "ProjectVersion"]
                        ]
                    }
                }
            ],
            'Applications': applist,
            'Steps': [
                {
                    "Name": "CreateDefaultHiveTables",
                    "ActionOnFailure": "CONTINUE",
                    "HadoopJarStep": {
                        "Jar": scriptRunnerJar,
                        "Args": [
                            "/mnt/tmp/aws-blog-emr-ranger/scripts/emr-steps/createHiveTables.sh",
                            event["ResourceProperties"]["StackRegion"]
                        ]
                    }
                },
                {
                    "Name": "LoadHDFSData",
                    "ActionOnFailure": "CONTINUE",
                    "HadoopJarStep": {
                        "Jar": scriptRunnerJar,
                        "Args": [
                            "/mnt/tmp/aws-blog-emr-ranger/scripts/emr-steps/loadDataIntoHDFS.sh",
                            event["ResourceProperties"]["StackRegion"]
                        ]
                    }
                },
                {
                    "Name": "InstallRangerServiceDef",
                    "ActionOnFailure": "CONTINUE",
                    "HadoopJarStep": {
                        "Jar": scriptRunnerJar,
                        "Args": [
                            "/mnt/tmp/aws-blog-emr-ranger/scripts/emr-steps/install-ranger-servicedef.sh",
                            event["ResourceProperties"]["RangerHostname"],
                            "s3://" + event["ResourceProperties"]["S3ArtifactBucket"] + "/" +
                            event["ResourceProperties"][
                                "S3ArtifactKey"] + "/" + event["ResourceProperties"][
                                "ProjectVersion"] + "/inputdata",
                            event["ResourceProperties"]["RangerHttpProtocol"],
                            event["ResourceProperties"]["RangerVersion"],
                            event["ResourceProperties"]["RangerAdminPassword"],
                            str(event["ResourceProperties"]
                                ["DefaultDomain"]).lower()
                        ]
                    }
                },
                {
                    "Name": "InstallRangerPolicies",
                    "ActionOnFailure": "CONTINUE",
                    "HadoopJarStep": {
                        "Jar": scriptRunnerJar,
                        "Args": [
                            "/mnt/tmp/aws-blog-emr-ranger/scripts/emr-steps/install-ranger-policies.sh",
                            event["ResourceProperties"]["RangerHostname"],
                            "s3://" + event["ResourceProperties"]["S3ArtifactBucket"] + "/" +
                            event["ResourceProperties"][
                                "S3ArtifactKey"] + "/" + event["ResourceProperties"][
                                "ProjectVersion"] + "/inputdata",
                            event["ResourceProperties"]["RangerHttpProtocol"],
                            event["ResourceProperties"]["RangerVersion"],
                            event["ResourceProperties"]["RangerAdminPassword"],
                            str(event["ResourceProperties"]
                                ["DefaultDomain"]).lower()
                        ]
                    }
                },
                {
                    "Name": "Hue-Permission-Update",
                    "ActionOnFailure": "CONTINUE",
                    "HadoopJarStep": {
                        "Jar": scriptRunnerJar,
                        "Args": [
                            "/mnt/tmp/aws-blog-emr-ranger/scripts/emr-steps/hue-update.sh"
                        ]
                    }
                },
                {
                    "Name": "Cloudformation-Signal",
                    "ActionOnFailure": "CONTINUE",
                    "HadoopJarStep": {
                        "Jar": scriptRunnerJar,
                        "Args": [
                            "/mnt/tmp/aws-blog-emr-ranger/scripts/emr-steps/send-cf-signal.sh",
                            event["ResourceProperties"]["SignalURL"]
                        ]
                    }
                }
            ],
            'VisibleToAllUsers': True,
            'JobFlowRole': event["ResourceProperties"]["JobFlowRole"],
            'ServiceRole': event["ResourceProperties"]["ServiceRole"],
            'Tags': [
                {
                    "Key": "Name",
                    "Value": "EMREC2Instance"
                }
            ],
            'Configurations': [
                {
                    "Classification": "core-site",
                    "Properties": {
                        "hadoop.proxyuser.knox.groups": "*",
                        "hadoop.proxyuser.knox.hosts": "*",
                        "hadoop.proxyuser.livy.groups": "*",
                        "hadoop.proxyuser.livy.hosts": "*",
                        "hadoop.proxyuser.hive.hosts": "*",
                        "hadoop.proxyuser.hive.groups": "*",
                        "hadoop.proxyuser.hue_hive.groups": "*"
                    },
                    "Configurations": []
                },
                {
                    "Classification": "livy-conf",
                    "Properties": {
                        "livy.superusers": "knox,hue,livy",
                        "livy.impersonation.enabled": "true",
                        "livy.repl.enable-hive-context": "true"
                    },
                    "Configurations": []
                },
                {
                    "Classification": "hcatalog-webhcat-site",
                    "Properties": {
                        "webhcat.proxyuser.knox.groups": "*",
                        "webhcat.proxyuser.knox.hosts": "*",
                        "webhcat.proxyuser.livy.groups": "*",
                        "webhcat.proxyuser.livy.hosts": "*",
                        "webhcat.proxyuser.hive.groups": "*",
                        "webhcat.proxyuser.hive.hosts": "*"
                    }
                },
                {
                    "Classification": "hadoop-kms-site",
                    "Properties": {
                        "hadoop.kms.proxyuser.knox.hosts": "*",
                        "hadoop.kms.proxyuser.knox.groups": "*",
                        "hadoop.kms.proxyuser.knox.users": "*",
                        "hadoop.kms.proxyuser.livy.users": "*",
                        "hadoop.kms.proxyuser.livy.groups": "*",
                        "hadoop.kms.proxyuser.livy.hosts": "*",
                        "hadoop.kms.proxyuser.hive.users": "*",
                        "hadoop.kms.proxyuser.hive.groups": "*",
                        "hadoop.kms.proxyuser.hive.hosts": "*"
                    },
                    "Configurations": []
                },
                {
                    "Classification": "hue-ini",
                    "Configurations": [
                        {
                            "Classification": "desktop",
                            "Properties": {
                                "app_blacklist": "search,indexer,impala"
                            },
                            "Configurations": [
                                {
                                    "Classification": "auth",
                                    "Properties": {
                                        "backend": "desktop.auth.backend.LdapBackend"
                                    }
                                },
                                {
                                    "Classification": "ldap",
                                    "Properties": {
                                        "base_dn": event["ResourceProperties"]["LDAPGroupSearchBase"],
                                        "bind_dn": event["ResourceProperties"]["LDAPBindUserName"] + '@' +
                                        event["ResourceProperties"]["DomainDNSName"],
                                        "bind_password": event["ResourceProperties"][
                                            "LDAPBindPassword"],
                                        "debug": "true",
                                        "force_username_lowercase": "true",
                                        "ignore_username_case": "true",
                                        "ldap_url": "ldap://" + event["ResourceProperties"][
                                            "LDAPHostPrivateIP"],
                                        "ldap_username_pattern": "uid:<username>," +
                                        event["ResourceProperties"][
                                            "LDAPSearchBase"],
                                        "nt_domain": event["ResourceProperties"]["DomainDNSName"],
                                        "search_bind_authentication": "true",
                                        "trace_level": "0",
                                        "sync_groups_on_login": "true",
                                        "create_users_on_login": "true",
                                        "use_start_tls": "false"
                                    }
                                }
                            ]
                        },
                        {
                            "Classification": "notebook",
                            "Properties": {
                                "interpreters_shown_on_wheel": "hive"
                            }
                        }
                    ],
                    "Properties": {
                    }
                }
            ],
            'Instances': {
                "InstanceGroups": [
                    {
                        "Name": "Master nodes",
                        "Market": "ON_DEMAND",
                        "InstanceRole": "MASTER",
                        "InstanceType": event["ResourceProperties"]["MasterInstanceType"],
                        "InstanceCount": int(event["ResourceProperties"]["MasterInstanceCount"]),
                    }
                ],
                "Ec2KeyName": event["ResourceProperties"]["KeyPairName"],
                "KeepJobFlowAliveWhenNoSteps": True,
                "TerminationProtected": False,
                "Ec2SubnetId": event["ResourceProperties"]["subnetID"],
                "AdditionalMasterSecurityGroups": [event["ResourceProperties"]["masterSG"]]
            }}

        if (int(event["ResourceProperties"]["CoreInstanceCount"]) > 0):
            cluster_parameters['Instances']['InstanceGroups'].append(
                {
                    "Name": "Slave nodes",
                    "Market": "ON_DEMAND",
                    "InstanceRole": "CORE",
                    "InstanceType": event["ResourceProperties"]["CoreInstanceType"],
                    "InstanceCount": int(event["ResourceProperties"]["CoreInstanceCount"])
                }
            )

        if event["ResourceProperties"]["EMRSecurityConfig"] != "false":
            cluster_parameters['SecurityConfiguration'] = event["ResourceProperties"]["EMRSecurityConfig"]
            cluster_parameters['KerberosAttributes'] = {
                "Realm": event["ResourceProperties"]["KerberosRealm"],
                "KdcAdminPassword": event["ResourceProperties"]["KdcAdminPassword"],
                "CrossRealmTrustPrincipalPassword": event["ResourceProperties"]["CrossRealmTrustPrincipalPassword"],
                "ADDomainJoinUser": event["ResourceProperties"]["ADDomainUser"],
                "ADDomainJoinPassword": event["ResourceProperties"]["ADDomainJoinPassword"]
            }

        if event["ResourceProperties"]["UseAWSGlueForHiveMetastore"] == "true":

            cluster_parameters['BootstrapActions'].append({
                "Name": "Apache Ranger - Glue Data Catalog Preview",
                "ScriptBootstrapAction": {
                    "Path": "s3://" + event["ResourceProperties"]["S3ArtifactBucket"] + "/" + event["ResourceProperties"][
                        "S3ArtifactKey"] + "/" + event["ResourceProperties"][
                        "ProjectVersion"] + "/scripts/ba_exec_background.sh",
                    "Args": [
                        "s3://" + event["ResourceProperties"]["S3ArtifactBucket"] + "/" + event["ResourceProperties"][
                            "S3ArtifactKey"] + "/" + event["ResourceProperties"][
                            "ProjectVersion"] + "/scripts/ba_ranger_glue_catalog_preview.sh"
                    ]
                }
            })

            cluster_parameters['Configurations'].append({
                "Classification": "hive-site",
                "Properties": {
                    "hive.server2.thrift.http.port": "10001",
                    "hive.server2.thrift.http.path": "cliservice",
                    "hive.server2.transport.mode": "binary",
                    "hive.server2.allow.user.substitution": "true",
                    "hive.server2.authentication.kerberos.principal": "hive/_HOST@" + event["ResourceProperties"]["DefaultDomain"],
                    "hive.server2.enable.doAs": "false",
                    "hive.metastore.client.factory.class": "com.amazonaws.glue.catalog.metastore.AWSGlueDataCatalogHiveClientFactory"
                }
            })
            cluster_parameters['Configurations'].append({
                "Classification": "spark-hive-site",
                "Properties": {
                    "hive.metastore.client.factory.class": "com.amazonaws.glue.catalog.metastore.AWSGlueDataCatalogHiveClientFactory"
                }
            })

        else:
            cluster_parameters['Configurations'].append({
                "Classification": "hive-site",
                "Properties": {
                    "javax.jdo.option.ConnectionURL": "jdbc:mysql://" + event["ResourceProperties"][
                        "DBHostName"] + ":3306/hive?createDatabaseIfNotExist=true",
                    "javax.jdo.option.ConnectionDriverName": "org.mariadb.jdbc.Driver",
                    "javax.jdo.option.ConnectionUserName": event["ResourceProperties"]["DBUserName"],
                    "javax.jdo.option.ConnectionPassword": event["ResourceProperties"]["DBRootPassword"],
                    "hive.server2.thrift.http.port": "10001",
                    "hive.server2.thrift.http.path": "cliservice",
                    "hive.server2.transport.mode": "binary",
                    "hive.server2.allow.user.substitution": "true",
                    "hive.server2.authentication.kerberos.principal": "hive/_HOST@" + event["ResourceProperties"]["DefaultDomain"],
                    "hive.server2.enable.doAs": "false"
                }
            })

        cluster_id = client.run_job_flow(**cluster_parameters)

        physical_resource_id = cluster_id["JobFlowId"]
        response_data = {
            "ClusterID": cluster_id["JobFlowId"]
        }
        return physical_resource_id, response_data

    except Exception as E:
        raise


def update(event, context):
    """
    Place your code to handle Update events here

    To return a failure to CloudFormation simply raise an exception, the exception message will be sent to
    CloudFormation Events.
    """
    physical_resource_id = event["PhysicalResourceId"]
    response_data = {}
    return physical_resource_id, response_data


def delete(event, context):
    client = boto3.client(
        "emr", region_name=event["ResourceProperties"]["StackRegion"])

    deleteresponse = client.terminate_job_flows(
        JobFlowIds=[
            event["PhysicalResourceId"]
        ]
    )

    response = client.describe_cluster(
        ClusterId=event["PhysicalResourceId"]
    )
    status = response["Cluster"]["Status"]["State"]

    response_data = {
        "ClusterStatus": status
    }

    return response_data


def handler(event, context):
    """
    Main handler function, passes off it's work to crhelper's cfn_handler
    """
    # update the logger with event info
    global logger
    logger = crhelper.log_config(event)
    return crhelper.cfn_handler(event, context, create, update, delete, logger,
                                init_failed)
