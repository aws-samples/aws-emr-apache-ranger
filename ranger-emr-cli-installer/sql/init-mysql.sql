ALTER USER 'root'@'localhost' IDENTIFIED BY '@MYSQL_ROOT_PASSWORD@';

DROP USER IF EXISTS 'root'@'%';
CREATE USER IF NOT EXISTS 'root'@'%' IDENTIFIED BY '@MYSQL_ROOT_PASSWORD@';
GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' WITH GRANT OPTION;
FLUSH PRIVILEGES;

# remove password validation plugin, in case password validation interrupt ranger installing scripts
UNINSTALL PLUGIN validate_password;

SET GLOBAL log_bin_trust_function_creators = 1;