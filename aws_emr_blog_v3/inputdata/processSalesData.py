from pyspark import SparkContext
from pyspark import SQLContext

# Initialize spark SQL context
sqlContext = SQLContext(sparkContext=sc)

# Join orders and products to get the sales rollup
products_sql = sqlContext.sql("select * from staging.products")
products_sql.registerTempTable("products")
products_sql.show(n=2)


# customers_sql = sqlContext.sql("select * from staging.customers")
# customers_sql.show(n=2)

# Load orders data from S3 into Datafram
orders_sql = sqlContext.sql("select order_date,price,sku from staging.orders")
orders_sql.registerTempTable("orders")

# Join orders and products to get the sales rollup
sales_breakup_sql = sqlContext.sql(""" 
        SELECT sum(orders.price) total_sales, products.sku, products.product_category
        FROM orders join products where orders.sku = products.sku
        group by products.sku, products.product_category
    """)

#products_all = products_sql.map(lambda p: "Counts: {0} Ipsum Comment: {1}".format(p.name, p.comment_col))
sales_breakup_sql.show(n=2)

# Write output back to s3 under processed
sales_breakup_sql.write.mode('overwrite'). \
    format("parquet").option("path", "s3://aws-datalake-security-data-vbhamidi-us-east-1/processed/sales/"). \
    saveAsTable("processed.sales")
