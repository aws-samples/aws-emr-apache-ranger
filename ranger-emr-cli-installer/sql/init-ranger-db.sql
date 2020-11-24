# When ranger scripts init database, it will check db connection and ranger db via assigned
# ranger db user and password, so create ranger db and db user is required! otherwise install
# will fail.

DROP DATABASE IF EXISTS ranger;
CREATE DATABASE IF NOT EXISTS ranger;

DROP USER IF EXISTS 'ranger'@'%';
CREATE USER IF NOT EXISTS 'ranger'@'%' IDENTIFIED BY '@MYSQL_RANGER_DB_USER_PASSWORD@';
GRANT ALL PRIVILEGES ON ranger.* TO 'ranger'@'%' WITH GRANT OPTION;
FLUSH PRIVILEGES;
