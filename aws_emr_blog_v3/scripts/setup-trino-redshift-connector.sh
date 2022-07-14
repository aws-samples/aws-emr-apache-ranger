sudo echo "connector.name=redshift
connection-url=jdbc:redshift://example.net:5439/database
connection-user=<user>
connection-password=<password>" > /etc/trino/conf.dist/catalog/redshift.properties
