$username = "Administrator"
ldap_admin_password=$1
ldap_bind_password=$2
ldap_default_user_password=$3
$domain= "corp.emr.local"
$searchdn="CN=Users,DC=corp,DC=emr,DC=local"
ldifde -i -f c:/load-users-new.ldf -s $domain -b $username $domain $ldap_admin_password | Out-File c:/log-out.txt -Append
dsmod user "CN=Hadoop Analyst1,$searchdn" -pwd $ldap_default_user_password -disabled no -d $domain -u $username -p $ldap_admin_password | Out-File c:/log-out.txt -Append
dsmod user "CN=Hadoop Analyst2,$searchdn" -pwd $ldap_default_user_password -disabled no -d $domain -u $username -p $ldap_admin_password | Out-File c:/log-out.txt -Append
dsmod user "CN=Hadoop Admin1,$searchdn" -pwd $ldap_default_user_password -disabled no -d $domain -u $username -p $ldap_admin_password | Out-File c:/log-out.txt -Append
dsmod user "CN=Bind User,$searchdn" -pwd $ldap_bind_password -disabled no -d $domain -u $username -p $ldap_admin_password | Out-File c:/log-out.txt -Append
