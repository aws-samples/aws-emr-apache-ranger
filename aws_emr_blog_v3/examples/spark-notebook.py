from pyspark import SparkContext
from pyspark import SQLContext

# Initialize spark SQL context
sqlContext = SQLContext(sparkContext=sc)

# Spark access allowed by the policy:
spark.sql("select * from tblanalyst1 limit 10").show()
# Spark access that will fail due to permission error:
spark.sql("select * from tblanalyst2 limit 10").show()
# S3 access allowed by the policy: `productsFile`
sqlContext.read.parquet("s3://aws-bigdata-blog/artifacts/aws-blog-emr-ranger/data/staging/products/")
# S3 access that will fail due to permission error: `customersFile`
sqlContext.read.parquet("s3://aws-bigdata-blog/artifacts/aws-blog-emr-ranger/data/staging/customers/")

# Create Table in Hive
# CREATE EXTERNAL TABLE IF NOT EXISTS students_s3 (name VARCHAR(64), address VARCHAR(64))
# PARTITIONED BY (student_id INT)
# STORED AS PARQUET
#LOCATION 's3://test-emr-security-ranger-beta-data/students_s3/'
studentsSQL = spark.sql("select * from default.students_s3")

spark.conf.set("hive.exec.dynamic.partition.mode", "nonstrict")
spark.sql("INSERT INTO students_s3 VALUES ('Amy Smith', '123 Park Ave, San Jose', 111111)")

studentsSQL.show()
