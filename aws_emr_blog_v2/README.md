# Authorization and Auditing on Amazon EMR Using Apache Ranger - V2
The repo contains code tied to [AWS Big Data Blog](https://aws.amazon.com/blogs/big-data/implementing-authorization-and-auditing-using-apache-ranger-on-amazon-emr/) on Implementing Authorization and Auditing on Amazon EMR Using Apache Ranger
This is V2 of the blog post with following updates

### Architecture:

![](../images/emr-ranger-v2.png)

### Updates:
- Apache Ranger 2.0 with RDS backed MySQL Database
- Windows AD server on EC2 (not SimpleAD)
- Choice of Hive Metastore [Choose one]:
    - RDS MySQL database (Default)
    - Glue Catalog
- Kerberos Enabled Amazon EMR cluster with
   * Ranger Plugins
     * HDFS
     * Apache Hive
     * Apache PrestoDB/PrestoSQL plugin (Optional)


The stack needs to be deployed in 2 steps.

 - Step 1 (step1_vpc-ec2-ad.template) [![Foo](../images/launch_stack.png)](https://console.aws.amazon.com/cloudformation/home?region=us-east-1#/stacks/new?stackName=EMRSecurityWithRangerBlogV2-Step1&templateURL=https://s3.amazonaws.com/aws-bigdata-blog/artifacts/aws-blog-emr-ranger/2.0/cloudformation/step1_vpc-ec2-ad.template) - Setup VPC, Bastion Host and AD servers
 - Step 2 (step2_ranger-rds-emr.template) [![Foo](../images/launch_stack.png)](https://console.aws.amazon.com/cloudformation/home?region=us-east-1#/stacks/new?stackName=EMRSecurityWithRangerBlogV2-Step2&templateURL=https://s3.amazonaws.com/aws-bigdata-blog/artifacts/aws-blog-emr-ranger/2.0/cloudformation/step2_ranger-rds-emr.template) - Setup RDS, Apache Ranger Server and EMR cluster
