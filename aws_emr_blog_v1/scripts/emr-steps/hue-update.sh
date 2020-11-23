#!/bin/bash

current_hostname=$(hostname -f)
hue_password=$(cat /dev/random | tr -dc '[:alnum:]' | head -c 16)

cat >~/hue.sql <<EOT
CREATE USER 'hue'@'%' IDENTIFIED BY '${hue_password}';
CREATE DATABASE huedb;
GRANT ALL PRIVILEGES ON \`huedb\`.* TO 'hue'@'%';
FLUSH PRIVILEGES;
EOT

sudo mysql < ~/hue.sql

sudo sed -i "s/engine = sqlite3/engine = mysql/g" /etc/hue/conf/hue.ini
sudo sed -i "s/name = \/var\/lib\/hue\/desktop.db/name = huedb/g" /etc/hue/conf/hue.ini

sudo sed -i "/.*name = huedb.*/a case_insensitive_collation = utf8_unicode_ci\ntest_charset = utf8\ntest_collation = utf8_bin\nhost = ${current_hostname}\nuser = hue\ntest_name = test_huedb\npassword = ${hue_password}\nport = 3306" /etc/hue/conf/hue.ini

cd /usr/lib/hue/apps
sudo make

sudo systemctl stop hue.service
sudo systemctl start hue.service
