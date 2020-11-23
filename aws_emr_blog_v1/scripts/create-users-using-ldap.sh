#!/bin/bash
set -euo pipefail
set -x
ldap_ip_address=$1
ldap_admin_password=$2
ldap_bind_password=$3
ldap_default_user_password=$4

start=0
ldapsearch -x -D "Administrator@corp.emr.local" -w $ldap_admin_password -H ldap://$ldap_ip_address -b "CN=Users,DC=corp,DC=emr,DC=local"
while [ $? -ne 0 ]; do
    sleep 30
    start=$(($start+1))
    echo $start
    if [[ $start -gt 6 ]];
    then
      break
    fi
    ldapsearch -x -D "Administrator@corp.emr.local" -w $ldap_admin_password -H ldap://$ldap_ip_address -b "CN=Users,DC=corp,DC=emr,DC=local"
done
ldapadd -x -D "Administrator@corp.emr.local" -w $ldap_admin_password -H ldap://$ldap_ip_address -f load-users-new.ldf
ldapmodify -v -x -D "Administrator@corp.emr.local" -w $ldap_admin_password -H ldap://$ldap_ip_address -f modify-users-new.ldf
password=$ldap_bind_password
password='"'$password'"'
u16pass=`printf $password|iconv -f ascii -t UTF16LE|base64`
echo "dn: CN=Bind User,CN=Users,DC=corp,DC=emr,DC=local" >ldap.ldif
echo "changetype: modify" >>ldap.ldif
echo "replace: unicodePwd" >>ldap.ldif
echo "unicodePwd:: $u16pass" >>ldap.ldif

password=$ldap_default_user_password
password='"'$password'"'
u16pass=`printf $password|iconv -f ascii -t UTF16LE|base64`
echo "" >> ldap.ldif
echo "dn: CN=Hadoop Analyst1,CN=Users,DC=corp,DC=emr,DC=local" >>ldap.ldif
echo "changetype: modify" >>ldap.ldif
echo "replace: unicodePwd" >>ldap.ldif
echo "unicodePwd:: $u16pass" >>ldap.ldif

password=$ldap_default_user_password
password='"'$password'"'
u16pass=`printf $password|iconv -f ascii -t UTF16LE|base64`
echo "" >> ldap.ldif
echo "dn: CN=Hadoop Analyst2,CN=Users,DC=corp,DC=emr,DC=local" >>ldap.ldif
echo "changetype: modify" >>ldap.ldif
echo "replace: unicodePwd" >>ldap.ldif
echo "unicodePwd:: $u16pass" >>ldap.ldif

password=$ldap_default_user_password
password='"'$password'"'
u16pass=`printf $password|iconv -f ascii -t UTF16LE|base64`
echo "" >> ldap.ldif
echo "dn: CN=Hadoop Admin1,CN=Users,DC=corp,DC=emr,DC=local" >>ldap.ldif
echo "changetype: modify" >>ldap.ldif
echo "replace: unicodePwd" >>ldap.ldif
echo "unicodePwd:: $u16pass" >>ldap.ldif

ldapmodify -v -x -D "Administrator@corp.emr.local" -w $ldap_admin_password -H ldap://$ldap_ip_address -f ldap.ldif
