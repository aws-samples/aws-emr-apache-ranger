-- This query shows how the Ranger Trino plugin uses column mask to NULL the ad_id and RowFilter to olny filter records with page = 'fox.com'
-- To update policies use: https://ranger-ga-1-1772333129.us-east-1.elb.amazonaws.com/index.html#!/service/4/policies/0
select * from default.tblanalyst1 limit 10;

-- Query fails as the user does not have access
-- To update policies use: https://ranger-ga-1-1772333129.us-east-1.elb.amazonaws.com/index.html#!/service/4/policies/0
select * from default.tblanalyst2 limit 10;

-- Query Redshift data using the Trino Redshift Connector
-- This query shows how the Ranger Trino plugin uses column mask to NULL the 'firstname' and RowFilter to olny filter records with city = 'Obaha'
-- To update policies use: https://ranger-ga-1-1772333129.us-east-1.elb.amazonaws.com/index.html#!/service/4/policies/0
select * from redshift.public.users limit 10;

-- Query fails as the user does not have access
-- To update policies use: https://ranger-ga-1-1772333129.us-east-1.elb.amazonaws.com/index.html#!/service/4/policies/0
select * from default.tblanalyst2 limit 10;
