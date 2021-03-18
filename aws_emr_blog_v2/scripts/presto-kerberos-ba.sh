#!/bin/bash

kdc_password=$1
PRESTO_PUPPET_DIR='/var/aws/emr/bigtop-deploy/puppet/modules/presto'

sudo sed -i "s/\$discovery_uri =.*/\$discovery_uri = \"https:\/\/\${discovery_host}:8446\"/" ${PRESTO_PUPPET_DIR}/manifests/init.pp
sudo sed -i "/class common/a \ \ \ \ \$kerberos_realm \ \ \ \ \ \ \ \ \ \ \ \ \ \ \ \ \ = \"\"," ${PRESTO_PUPPET_DIR}/manifests/init.pp
sudo sed -i "/class common/a \ \ \ \ \$my_hive_host \ \ \ \ \ \ \ \ \ \ \ \ \ \ \ \ \ \ \ = \"\"," ${PRESTO_PUPPET_DIR}/manifests/init.pp

sudo bash -c "cat > /tmp/presto-kerberos.txt" <<'EOF'

   # Presto configuration for Kerberized clusters
   if ($kerberos_realm != "") {
      require kerberos::client
      kerberos::host_keytab { "presto":
        spnego => true,
        require => Package["presto"],
      }
    }

    file { '/usr/bin/presto-cli':
      ensure => file,
      mode   => 0755,
      owner  => root,
      group  => root,
      content => template('presto/presto-cli'),
      require => Package['presto']
    }

EOF

sudo sed -i "/notice/r /tmp/presto-kerberos.txt" ${PRESTO_PUPPET_DIR}/manifests/init.pp
sudo rm -f /tmp/presto-kerberos.txt
sudo sed -i "/subscribe/a \ \ \ \ \ \ \ \ File\[\'\/usr\/bin\/presto-cli\'\]," ${PRESTO_PUPPET_DIR}/manifests/init.pp

CLUSTER_YAML='/var/aws/emr/bigtop-deploy/puppet/hieradata/bigtop/cluster.yaml'

sudo bash -c "cat >> ${CLUSTER_YAML}" <<'EOF'

presto::common::kerberos_realm: "%{hiera('kerberos::site::realm')}"
presto::common::my_hive_host: "%{hiera('bigtop::hadoop_head_node')}"

EOF


sudo bash -c "cat >> ${PRESTO_PUPPET_DIR}/templates/hive.properties" <<'EOF'

<% if @kerberos_realm != "" -%>
hive.metastore.authentication.type=KERBEROS
hive.metastore.service.principal=hive/<%= @my_hive_host %>@<%= @kerberos_realm %>
hive.metastore.client.principal=presto/<%= @fqdn %>@<%= @kerberos_realm %>
hive.metastore.client.keytab=/etc/presto.keytab

hive.hdfs.wire-encryption.enabled = true
<% end -%>

EOF


sudo bash -c "cat >> ${PRESTO_PUPPET_DIR}/templates/config.properties" <<'EOF'

<% if @kerberos_realm != "" -%>
node.internal-address = <%= @fqdn %>
http-server.https.enabled = true
http-server.https.port = 8446
internal-communication.https.required = true

http-server.authentication.type=KERBEROS
http.server.authentication.krb5.service-name=presto
http.server.authentication.krb5.keytab=/etc/presto.keytab
http.authentication.krb5.config=/etc/krb5.conf
internal-communication.kerberos.enabled=true
<% end -%>

EOF


sudo bash -c "cat >> ${PRESTO_PUPPET_DIR}/templates/presto-env.sh" <<'EOF'

export EXTRA_ARGS="--server https://<%= @my_hive_host %>:8446 \
--truststore-path /usr/share/aws/emr/security/conf/truststore.jks \
--truststore-password PASSWORD \
--krb5-config-path /etc/krb5.conf \
--krb5-remote-service-name presto
--keystore-path /usr/share/aws/emr/security/conf/truststore.jks \
--keystore-password PASSWORD"

EOF


sudo bash -c "cat > ${PRESTO_PUPPET_DIR}/templates/presto-cli" <<'EOF'
#!/bin/bash
source /etc/presto/conf/presto-env.sh
PRESTO_HOME=/usr/lib/presto
export PATH=$JAVA8_HOME/bin:$PATH

USER_TICKET_CACHE=$(klist | grep cache | cut -d ':' -f3)
USER_KRB_PRINCIPAL=$(klist | grep Default | cut -d':' -f2 | tr -d ' ')

$PRESTO_HOME/bin/presto-cli-0.227-executable ${EXTRA_ARGS} --krb5-principal ${USER_KRB_PRINCIPAL} --krb5-credential-cache-path ${USER_TICKET_CACHE} "$@"

EOF

exit 0
