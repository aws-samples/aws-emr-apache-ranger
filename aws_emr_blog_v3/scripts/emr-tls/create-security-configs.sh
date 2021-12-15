#!/bin/bash

ENV=$1

if [ -z "$ENV" ]
then
      echo "ENV is empty"
      exit 1
fi

# SSL
RANGER_ADMIN_CERT="emr/$ENV/rangerGAservercert"
RANGER_AGENT_KEY="emr/$ENV/rangerGAagentkey"

# Kerberos
KerberosADdomain=""
DomainDNSName=""

# GDP Constants
AWS_PROFILE="data"
AWS_REGION="us-east-1"
AWS_ACCOUNT="308852840113"

# Environment-specific Variables
if [ "$ENV" = "lab" ]; then
  AWS_ROLE="EMR_EC2_LabInfrastructureRole"
  RANGER_URL="https://lab-ranger.gdp.data.grubhub.com"
  PRETTY_ENV="Lab"
else
  echo "Invalid Environment: $ENV"
fi


aws --profile $AWS_PROFILE emr delete-security-configuration --name "$PRETTY_ENV Ranger" \
  && echo "Deleted Security Configuration for $PRETTY_ENV" && sleep 30

# Not Required:

#CLOUDWATCH_AUDIT=",
#      \"AuditConfiguration\": {
#        \"Destinations\": {
#          \"AmazonCloudWatchLogs\": {
#            \"CloudWatchLogGroup\": \"arn:aws:logs:$AWS_REGION:$AWS_ACCOUNT:log-group:emr-$ENV-ranger\"
#          }
#        }
#      }"

aws --profile $AWS_PROFILE emr create-security-configuration --name "$PRETTY_ENV Ranger" --security-configuration "{
  \"AuthenticationConfiguration\":{
    \"KerberosConfiguration\":{
      \"Provider\":\"ClusterDedicatedKdc\",
      \"ClusterDedicatedKdcConfiguration\":{
        \"TicketLifetimeInHours\":24,
        \"CrossRealmTrustConfiguration\":{
          \"Realm\":\"$KerberosADdomain\",
          \"Domain\":\"$DomainDNSName\",
          \"AdminServer\":\"$DomainDNSName\",
          \"KdcServer\":\"$DomainDNSName\"
        }
      }
    }
  },
  \"AuthorizationConfiguration\": {
    \"RangerConfiguration\": {
      \"AdminServerURL\": \"$RANGER_URL\",
      \"RoleForRangerPluginsARN\": \"arn:aws:iam::$AWS_ACCOUNT:role/$AWS_ROLE\",
      \"RoleForOtherAWSServicesARN\": \"arn:aws:iam::$AWS_ACCOUNT:role/$AWS_ROLE\",
      \"AdminServerSecretARN\": \"arn:aws:secretsmanager:$AWS_REGION:$AWS_ACCOUNT:secret:$RANGER_ADMIN_CERT\",
      \"RangerPluginConfigurations\": [
        {
          \"App\": \"Spark\",
          \"ClientSecretARN\": \"arn:aws:secretsmanager:$AWS_REGION:$AWS_ACCOUNT:secret:$RANGER_AGENT_KEY\",
          \"PolicyRepositoryName\": \"lab-hive\"
        },
        {
          \"App\": \"Hive\",
          \"ClientSecretARN\": \"arn:aws:secretsmanager:$AWS_REGION:$AWS_ACCOUNT:secret:$RANGER_AGENT_KEY\",
          \"PolicyRepositoryName\": \"lab-hive\"
        },
        {
          \"App\": \"EMRFS-S3\",
          \"ClientSecretARN\": \"arn:aws:secretsmanager:$AWS_REGION:$AWS_ACCOUNT:secret:$RANGER_AGENT_KEY\",
          \"PolicyRepositoryName\": \"lab-awss3\"
        }
      ]$CLOUDWATCH_AUDIT
    }
  }
}"
