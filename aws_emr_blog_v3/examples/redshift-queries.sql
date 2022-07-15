create table public.products (company VARCHAR, link VARCHAR, price FLOAT, product_category VARCHAR, release_date VARCHAR, sku VARCHAR);

COPY public.products
FROM 's3://aws-bigdata-blog/artifacts/aws-blog-emr-ranger/data/staging/products/'
IAM_ROLE '<>'
FORMAT AS PARQUET;
