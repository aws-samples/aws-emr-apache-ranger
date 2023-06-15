set -ex

bucket=$1  # change this to customer bucket
# please make sure this file exist
# s3://<customer_bucket>/rpms/ranger-trino-plugin/ranger-trino-plugin-2.0.1.amzn.4-1.amzn2.noarch.rpm
local_repo=/var/aws/emr/packages/bigtop

exclude_pkgs=""
apps=("ranger-trino-plugin")
file_name="ranger-trino-plugin-2.0.1.amzn.4-1.amzn2.noarch.rpm"

for app in ${apps[@]}; do
  sudo mkdir -p $local_repo/$app
  sudo aws s3 cp $bucket/rpms/$app/$file_name $local_repo/$app/$file_name
  exclude_pkgs="$exclude_pkgs $app*"
done

repo=""
flag=true
# For pre emr-5.10.0 clusters
if [ -e "/etc/yum.repos.d/Bigtop.repo" ]
then
  flag=false
# For emr-5.10.0+ clusters
elif [ -e "/etc/yum.repos.d/emr-apps.repo" ]
then
  repo="/etc/yum.repos.d/emr-apps.repo"
# For BYOA clusters
elif [ -e "/etc/yum.repos.d/emr-bigtop.repo" ]
then
  repo="/etc/yum.repos.d/emr-bigtop.repo"
fi

if [ "$flag" = true ]
then
  sudo bash -c "cat >> $repo" <<EOL
exclude =$exclude_pkgs
EOL
fi

sudo yum install -y createrepo
sudo createrepo --update --workers 8 -o $local_repo $local_repo
sudo yum clean all

if [ "$flag" = true ]
then
  sudo bash -c "cat > /etc/yum.repos.d/bigtop_test.repo" <<EOL
[bigtop_test]
name=bigtop_test_repo
baseurl=file:///var/aws/emr/packages/bigtop
enabled=1
gpgcheck=0
priority=4
EOL
fi