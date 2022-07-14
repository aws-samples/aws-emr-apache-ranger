#!/bin/bash

TRUST_STORE_PASS=amazon
KEY_STORE_PASS=amazon

HUE_INI='/etc/hue/conf.empty/hue.ini'

sudo bash -c "cat > /usr/bin/trino-cli" <<'EOF'
#!/bin/bash
source /etc/trino/conf/trino-env.sh
TRINO_HOME=/usr/lib/trino
export PATH=$JAVA8_HOME/bin:$PATH

USER_TICKET_CACHE=$(klist | grep cache | cut -d ':' -f3)
USER_KRB_PRINCIPAL=$(klist | grep Default | cut -d':' -f2 | tr -d ' ')

$TRINO_HOME/bin/trino-cli-*-executable ${EXTRA_ARGS} --krb5-principal ${USER_KRB_PRINCIPAL} --krb5-credential-cache-path ${USER_TICKET_CACHE} "$@"

EOF

hue_trino_config() {
  echo "Configuring Hue"
  KrbREALM=$(sudo cat /etc/krb5.conf | grep default_realm | cut -d'=' -f2 | tr -d '[:blank:]')
  HuetrinoKeytab='/etc/hue-trino.keytab'
  KeyStorePath='/usr/lib/trino/etc/trino-client-truststore.jks'
  TrustStorePath="$JAVA_HOME/lib/security/cacerts"

  TRINO_JDBC_URL="jdbc:trino://$(hostname -f):7778/hive/default?SSL=true\&SSLKeyStorePath=${KeyStorePath}\&SSLKeyStorePassword=${KEY_STORE_PASS}\&\
SSLTrustStorePath=${TrustStorePath}\&SSLTrustStorePassword=${TRUST_STORE_PASS}\&KerberosConfigPath=/etc/krb5.conf\&\
KerberosKeytabPath=${HuetrinoKeytab}\&KerberosPrincipal=trino/$(hostname -f)@${KrbREALM}\&KerberosRemoteServiceName=trino\&KerberosUseCanonicalHostname=false"

  trinoOpts='options='"'"'{"url": "'"${TRINO_JDBC_URL}"'","driver": "io.trino.jdbc.TrinoDriver","user":"","password":""}'"'"

  sudo cp /etc/trino.keytab /etc/hue-trino.keytab
  sudo chown hue:hue /etc/hue-trino.keytab
  sudo sed -i "s|.*io.trino.jdbc.TrinoDriver.*|$trinoOpts|" ${HUE_INI}

  sudo sed -i "s|.*pam_service=login| pam_service=login|" ${HUE_INI}
  sudo sed -i "s|backend.*desktop.auth.backend.AllowFirstUserDjangoBackend.*|backend=desktop.auth.backend.PamBackend|" ${HUE_INI}

  sudo systemctl restart hue
}

if [ -f "${HUE_INI}" ]; then
    hue_trino_config
fi

exit 0
