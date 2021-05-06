## Authorization and Auditing on Amazon EMR Using Apache Ranger

The repo provides reference architecture to deploy [Apache Ranger](https://ranger.apache.org/) on [Amazon EMR](https://aws.amazon.com/emr/). Apache Ranger is a framework to enable, monitor, and manage comprehensive data security across the Hadoop platform. 
Features include centralized security administration, 
fine-grained authorization across many Hadoop components (eg - Hadoop, Hive, HBase, Storm, Knox, Solr, Kafka, and YARN) and central auditing. 
It uses agents to sync policies and users, and plugins that run within the same process as the Hadoop component, like NameNode and HiveServer2.

The repo contains code tied to [AWS Big Data Blog](https://aws.amazon.com/blogs/big-data/implementing-authorization-and-auditing-using-apache-ranger-on-amazon-emr/).

> **NOTE:** the code has gone through unit and functional test against a **few recent versions** of Amazon EMR. 
> It is likely that it may not work with **all** EMR versions.
> Code/plugin marked as **beta** has not been suitable for production use.
>> Please submit Pull Request or to create an [Issue](https://github.com/aws-samples/aws-emr-apache-ranger/issues/new)
>
### Deployment options: 

| Module | Description| Architecture | Details |
| ------ | -------| --- |-------------------------------------------------------- |
| V1 | [Open Source Ranger Plugins with LDAP](aws_emr_blog_v1) |  ![](images/simple-ad-setup.png) | Basic deployment using [AWS Simple AD](https://docs.aws.amazon.com/directoryservice/latest/admin-guide/directory_simple_ad.html), Hive and HDFS plugins and optional Presto Plugin|
| V2 | [Open Source Ranger Plugins with Kerberos enabled cluster and AD](aws_emr_blog_v2) |  ![](images/emr-ranger-v2.png) | Deploy a Kerberos enabled EMR cluster using Windows AD, Hive and HDFS plugins and optional Presto and HBase Plugin|
| V3 | [EMR Native plugins for Spark/S3 with Kerberos enabled cluster and AD](aws_emr_blog_v3) |  ![](images/emr-ranger-v3.png) | Deploy a Kerberos enabled EMR cluster with the Amazon EMR native integration of Apache Ranger - Supports Hive, Spark and Amazon S3|

### Compatibility/Supported plugins: 
| Module|  Tag | Region| Region Code | Cloudformation stack | Apache Ranger Version | EMR Version | Supported Plugins|
| -------| --- | --- | --- | --- | --- | --- |-------------------------------------------------------- |
| V1 | [1.0](https://github.com/aws-samples/aws-emr-apache-ranger/tree/1.0) | All| All| [![Foo](images/launch_stack.png)](https://console.aws.amazon.com/cloudformation/home?region=us-east-1#/stacks/new?stackName=EMRSecurityWithRangerBlogV1&templateURL=https://s3.amazonaws.com/aws-bigdata-blog/artifacts/aws-blog-emr-ranger/1.0/cloudformation/nestedstack.template) | Apache Ranger 1.0, 2.1 | emr-5.28.1, emr-5.29.0, emr-5.30.1| Hive 2.x, Hadoop 2.x, PrestoDB 0.227/0.232 (Presto plugin needs Ranger 2.0) | 
| V1 | [1.1](https://github.com/aws-samples/aws-emr-apache-ranger/tree/1.1) | All| All| [![Foo](images/launch_stack.png)](https://console.aws.amazon.com/cloudformation/home?region=us-east-1#/stacks/new?stackName=EMRSecurityWithRangerBlogV1&templateURL=https://s3.amazonaws.com/aws-bigdata-blog/artifacts/aws-blog-emr-ranger/1.1/cloudformation/nestedstack.template) | Apache Ranger 2.2 | emr-5.29.0, emr-5.30.1, emr-6.1.0 | Hive 3.x, Hadoop 3.x, PrestoSQL 338 OR PrestoDB 0.232 | 
| V2 | [2.0](aws_emr_blog_v2) | US East (Virginia)| us-east-1| Step1 - Setup VPC/AD server - [![Foo](images/launch_stack.png)](https://console.aws.amazon.com/cloudformation/home?region=us-east-1#/stacks/new?stackName=EMRSecurityWithRangerBlogV2-Step1&templateURL=https://s3.amazonaws.com/aws-bigdata-blog/artifacts/aws-blog-emr-ranger/2.0/cloudformation/step1_vpc-ec2-ad.template) <br /> <br /> Step 2 -  Setup the Ranger Server/RDS Instance/EMR Cluster - [![Foo](images/launch_stack.png)](https://console.aws.amazon.com/cloudformation/home?region=us-east-1#/stacks/new?stackName=EMRSecurityWithRangerBlogV2-Step2&templateURL=https://s3.amazonaws.com/aws-bigdata-blog/artifacts/aws-blog-emr-ranger/2.0/cloudformation/step2_ranger-rds-emr.template) | Apache Ranger 2.1 | emr-5.30.1, emr-6.1.0, emr-6.2.0 | Hive 2.x, Hadoop 2.x, PrestoSQL 338/343, PrestoDB 0.227/0.232 (Presto plugin needs Ranger 2.0) | 
| V3 EMR Ranger GA Launch | [3.0](aws_emr_blog_v3) | US East (Virginia)| us-east-1| Step1 - Use this script to Upload SSL key and certs to AWS Secrets Manager [Script](aws_emr_blog_v3/scripts/emr-tls/create-tls-certs.sh) <br /> Step2 - Setup VPC/AD server [![Foo](images/launch_stack.png)](https://console.aws.amazon.com/cloudformation/home?region=us-east-1#/stacks/new?stackName=EMRSecurityWithRangerBlogV3-Step1&templateURL=https://s3.amazonaws.com/aws-bigdata-blog/artifacts/aws-blog-emr-ranger/3.0/cloudformation/step1_vpc-ec2-ad.template) <br /> Step 3 -  Setup the Ranger Server/RDS Instance/EMR Cluster [![Foo](images/launch_stack.png)](https://console.aws.amazon.com/cloudformation/home?region=us-east-1#/stacks/new?stackName=EMRSecurityWithRangerBlogV3-Step2&templateURL=https://s3.amazonaws.com/aws-bigdata-blog/artifacts/aws-blog-emr-ranger/3.0/cloudformation/step2_ranger-rds-emr.template) | Apache Ranger 2.1 | emr-5.32.0 | Hive 2.x, Hadoop 2.x, Spark 2.x | 

> WARNING: The current V1 setup does not enable strong cluster level Auth (Kerberos) for EMR. Only LDAP enabled Hue UI. V2 will support Kerberos - refer to the [roadmap](https://github.com/aws-samples/aws-emr-apache-ranger/projects/1) for details.

----

### Module V3 - Native Support of Apache Ranger on Amazon EMR 5.32+

#### Apache Spark Plugin
![](images/emr-ranger-spark.gif)

#### Amazon S3 Plugin

![](images/emr-ranger-s3.gif)

----

### Module V1 (1.1) PrestoSQL Ranger plugin (EMR 6.1 & Ranger 2.2)
Shows how the plugin can be used to enable column level access controls, column masking and row filter. Demo uses the [Presto Redshift connector](https://prestosql.io/docs/current/connector/redshift.html). The same functionality should work with other [Presto connectors](https://prestosql.io/docs/current/connector.html).

![](images/prestosql_ranger_plugin.gif)

Please open Git Issues if you would like to see updates/other plugin integrations. 
### References:

 - Amazon EMR: https://aws.amazon.com/emr/
 - EMRFS: https://docs.aws.amazon.com/emr/latest/ManagementGuide/emr-fs.html
 - Amazon EMR + Kerberos: https://docs.aws.amazon.com/emr/latest/ManagementGuide/emr-kerberos.html 
 - Apache Ranger: https://ranger.apache.org/
 - Apache Ranger + Amazon EMR Blog: https://aws.amazon.com/blogs/big-data/implementing-authorization-and-auditing-using-apache-ranger-on-amazon-emr/
 - Apache Ranger Presto Plugin: 
   - Code for PrestoDB plugin - [Link](https://github.com/varunrao/ranger/tree/prestodb)
   - https://cwiki.apache.org/confluence/display/RANGER/Presto+Plugin


# Reporting Bugs

If you encounter a bug, please create a new issue with as much detail as possible and steps for reproducing the bug. See the [Contributing Guidelines](./CONTRIBUTING.md) for more details.

# License

This sample code is made available under a modified MIT license. See the LICENSE file.
