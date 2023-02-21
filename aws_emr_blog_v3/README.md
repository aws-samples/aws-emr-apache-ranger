# Native Support for Authorization and Auditing on Amazon EMR Using Apache Ranger 

The repo contains code tied to the AWS Big Data Blog introducing native Apache Ranger integration with Amazon EMR
The code deploys the following:

- Apache Ranger 2.0
- Windows AD server on EC2 (Creates dummy users - binduser/analyst1/analyst2)
- RDS MySQL database that is used for Apache Ranger and Hive Metastore on the EMR cluster
- Kerberos Enabled Amazon EMR cluster (EMR 5.32) with AWS Managed Ranger Plugins
     * Amazon S3
     * Apache Hive
        * Blog -  <a href="https://aws.amazon.com/blogs/big-data/introducing-amazon-emr-integration-with-apache-ranger/" target="_blank">Introducing Amazon EMR integration with Apache Ranger</a>
     * Apache Spark
        * Blog - [Authorize SparkSQL data manipulation on Amazon EMR using Apache Ranger](https://aws.amazon.com/blogs/big-data/authorize-sparksql-data-manipulation-on-amazon-emr-using-apache-ranger/){:target="_blank"}
     * Apache Tino (> EMR 6.7)
       * Blog (**New!**) - [Enable federated governance using Trino and Apache Ranger on Amazon EMR](https://aws.amazon.com/blogs/big-data/enable-federated-governance-using-trino-and-apache-ranger-on-amazon-emr/){:target="_blank"}

> **NOTE:** the code only run under us-east-1 (N. Virginia). You can copy to your regional bucket to deploy in a different region. Also, create [Issue](https://github.com/aws-samples/aws-emr-apache-ranger/issues/new) if you would like support for additional regions using this repo. 
>

### NOTE: Apache Ranger plugins and Apache Ranger Admin Server SSL Keys and Certs have to be uploaded to AWS Secrets Manager for Cloudformation scripts to work

## Cloudformation Launch Steps:

Review these active items currenlty in under the V3 main branch [https://github.com/aws-samples/aws-emr-apache-ranger/projects/1?card_filter_query=label%3Av3]

 1. Create VPC/AD server (takes ~10 min to run) [![Foo](../images/launch_stack.png)](https://console.aws.amazon.com/cloudformation/home?region=us-east-1#/stacks/new?stackName=EMRSecurityWithRangerBlogV3-Step1&templateURL=https://s3.amazonaws.com/aws-bigdata-blog/artifacts/aws-blog-emr-ranger/v3/cloudformation/step1_vpc-ec2-ad.template){:target="_blank"}
    - NOTE: The 'beta' code supports multi-region deployment by creating a new regional bucket
 2. Setup the Ranger Server/RDS Instance/EMR Cluster (takes ~15 min to run) [![Foo](../images/launch_stack.png)](https://console.aws.amazon.com/cloudformation/home?region=us-east-1#/stacks/new?stackName=EMRSecurityWithRangerBlogV3-Step2&templateURL=https://s3.amazonaws.com/aws-bigdata-blog/artifacts/aws-blog-emr-ranger/v3/cloudformation/step2_ranger-rds-emr.template){:target="_blank"}
  - NOTE: The 'V3' code now supports multi-region deployment by creating a new regional bucket. Make sure you select the following parameter values to allow multi-region deployment (required is cluster in not in US-EAST-1) and automatic creation of the self-signed certs required by EMR for Ranger integration. 
    - **CreateRegionalS3BucketAndCopyScripts: 'true'** -- Will create a regional bucket and copy the required files
    - **CreateTLSCerts: 'true'** -- Will create self-signed certs and upload to Secrets manager
    
    ![image](https://user-images.githubusercontent.com/1559391/211591074-7260e5f7-3fd0-4e82-9d81-fbdc93350d70.png)
    ![image](https://user-images.githubusercontent.com/1559391/211591175-45e592ca-7207-47f6-8f79-77cda7154d2d.png)

## (BETA code) Cloudformation Launch Steps:
All active development code is under the Beta branch. Review these active items currenlty in Beta (https://github.com/aws-samples/aws-emr-apache-ranger/projects/1?card_filter_query=label%3Abeta). NOTE: It may not be fully tested and may not work with all EMR versions.

Steps to deploy the Beta stack:

 1. Create VPC/AD server (takes ~10 min to run) [![Foo](../images/launch_stack.png)](https://console.aws.amazon.com/cloudformation/home?region=us-east-1#/stacks/new?stackName=EMRSecurityWithRangerBlogV3-Step1&templateURL=https://s3.amazonaws.com/aws-bigdata-blog/artifacts/aws-blog-emr-ranger/beta/cloudformation/step1_vpc-ec2-ad.template){:target="_blank"}
    - NOTE: The 'beta' code supports multi-region deployment by creating a new regional bucket
 2. Setup the Ranger Server/RDS Instance/EMR Cluster (takes ~15 min to run) [![Foo](../images/launch_stack.png)](https://console.aws.amazon.com/cloudformation/home?region=us-east-1#/stacks/new?stackName=EMRSecurityWithRangerBlogV3-Step2&templateURL=https://s3.amazonaws.com/aws-bigdata-blog/artifacts/aws-blog-emr-ranger/beta/cloudformation/step2_ranger-rds-emr.template){:target="_blank"}
  - NOTE: The 'beta' code supports multi-region deployment by creating a new regional bucket. Make sure you select the following parameter values:
    - **CreateRegionalS3BucketAndCopyScripts: 'true'** -- Will create a regional bucket and copy the required files
    - **CreateTLSCerts: 'true'** -- Will create self-signed certs and upload to Secrets manager
    
    ![image](https://user-images.githubusercontent.com/1559391/211591074-7260e5f7-3fd0-4e82-9d81-fbdc93350d70.png)
    ![image](https://user-images.githubusercontent.com/1559391/211591175-45e592ca-7207-47f6-8f79-77cda7154d2d.png)


## Test
 - Login to the cluster (Apache Zeppelin, Hue, Livy or SSH)
    - ``> pyspark``
 - Spark access allowed by the policy: `spark.sql("select * from tblanalyst1 limit 10").show()`
 - Spark access that will fail due to permission error: `spark.sql("select * from tblanalyst2 limit 10").show()`
 - S3 access allowed by the policy: `productsFile = sqlContext.read.parquet("s3://aws-bigdata-blog/artifacts/aws-blog-emr-ranger/data/staging/products/")`
 - S3 access that will fail due to permission error: `customersFile = sqlContext.read.parquet("s3://aws-bigdata-blog/artifacts/aws-blog-emr-ranger/data/staging/customers/")`

## Architecture

![](../images/emr-ranger-v3.png)

## Cloudformation stack output

![](../images/emr-ranger-v3-cfn.png)

## Features support by Amazon EMR Trino Plugin

### Row filter and column masking

![](../images/emr-ranger-v3-trino-row-filter-column-mask.png)

### Authorize calls to trino connectors

![](../images/emr-ranger-v3-trino-authorize-trino-connectors.png)

### Dynamic row filters based on lookup table and user session

![](../images/emr-ranger-v3-trino-dynamic-row-filters.png)
