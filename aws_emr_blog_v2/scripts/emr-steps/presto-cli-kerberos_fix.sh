#!/bin/bash
emr_version=$1
presto_engine=$2

#TRUST_STORE_PASS=$(sudo cat /etc/presto/conf/config.properties | grep 'internal-communication.https.keystore.key' | cut -d '=' -f2 | tr -d ' ')
#
#sudo sed -i "s/.*8889.*//" /etc/presto/conf/presto-env.sh
#
#sudo sed -i "s/PASSWORD/${TRUST_STORE_PASS}/g" /etc/presto/conf/presto-env.sh
if [ "$presto_engine" == "PrestoSQL" ]; then
  TRUST_STORE_PASS=$(sudo cat /etc/presto/conf/config.properties | grep 'internal-communication.https.truststore.key' | cut -d '=' -f2 | tr -d ' ')
else
  TRUST_STORE_PASS=$(sudo cat /etc/presto/conf/config.properties | grep 'internal-communication.https.keystore.key' | cut -d '=' -f2 | tr -d ' ')
fi

sudo keytool -importkeystore -srckeystore /usr/share/aws/emr/security/conf/truststore.jks \
  -destkeystore /usr/lib/jvm/java/jre/lib/security/cacerts -deststorepass changeit -srcstorepass $TRUST_STORE_PASS

exit 0


