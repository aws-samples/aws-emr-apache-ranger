# Authorization and Auditing on Amazon EMR Using Apache Ranger - V2
The repo contains code tied to [AWS Big Data Blog](https://aws.amazon.com/blogs/big-data/implementing-authorization-and-auditing-using-apache-ranger-on-amazon-emr/) on Implementing Authorization and Auditing on Amazon EMR Using Apache Ranger
This is V2 of the blog post with following updates

- Apache Ranger 2.0 with RDS backed MySQL Database
- Windows AD server on EC2
- Choice of Hive Metastore [Choose one]:
    - RDS MySQL database
    - Glue Catalog
- Kerberos Enabled Amazon EMR cluster with
   * Ranger Plugins
     * HDFS
     * Apache Hive
     * Optional Apache PrestoDB/PrestoSQL plugin


The stack needs to be deployed in 2 steps.

 - Step 1 (step1_vpc-ec2-ad.template) - Setup VPC, Bastion Host and AD servers
 - Step 2 (step2_ranger-rds-emr.template) - Setup RDS, Apache Ranger Server and EMR cluster
