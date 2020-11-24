#!/usr/bin/env bash

# ------------------------------------------------   JDK Operations   ------------------------------------------------ #

installJdk8IfNotExists() {
    rpm -q java-1.8.0-openjdk-devel &>/dev/null
    if [ ! "$?" = "0" ]; then
        printHeading "INSTALL OPEN JDK8"
        yum -y install java-1.8.0-openjdk-devel &>/dev/null
        echo "export JAVA_HOME=$JAVA_HOME;export PATH=$JAVA_HOME/bin:$PATH" > /etc/profile.d/java.sh
        source /etc/profile.d/java.sh
    fi
}

# -------------------------------------------------   AD Operations   ------------------------------------------------ #

testLdapConnectivity() {
    printHeading "TEST AD/LDAP CONNECTIVITY"
    ldapsearch -VV &>/dev/null
    if [ ! "$?" = "0" ]; then
        echo "Install ldapsearch for AD connectivity test"
        yum -y install openldap-clients &>/dev/null
    fi
    if [ "$AUTH_TYPE" = "ad" ]; then
        echo "Searched following dn from Windows AD server with given configs:"
        ldapsearch -x -LLL -D "$AD_BIND_DN" -w "$AD_BIND_PASSWORD" -H "$AD_URL" -b "$AD_BASE_DN" dn
    elif [ "$AUTH_TYPE" = "ldap" ]; then
        echo "Searched following dn from OpenLDAP server with given configs:"
        ldapsearch -x -LLL -D "$LDAP_BIND_DN" -w "$LDAP_BIND_PASSWORD" -H "$LDAP_URL" -b "$LDAP_BASE_DN" dn
    else
        echo "Invalid authentication type, only AD and LDAP are supported!"
        exit 1
    fi

    if [ "$?" = "0" ]; then
        echo "Connecting to ad/ldap server is SUCCESSFUL!!"
    else
        echo "Connecting to ad/ldap server is FAILED!!"
        exit 1
    fi
}

# -----------------------------------------------   MySQL Operations   ----------------------------------------------- #

installMySqlIfNotExists() {
    systemctl --type=service --state=running | grep mysqld
    if [ ! "$?" = "0" ]; then
        printHeading "INSTALL MYSQL"
        if [ ! -f /tmp/mysql57-community-release-el7-11.noarch.rpm ]; then
            wget https://dev.mysql.com/get/mysql57-community-release-el7-11.noarch.rpm -P /tmp/
        fi
        rpm -ivh /tmp/mysql57-community-release-el7-11.noarch.rpm
        yum -y install mysql-community-server
        systemctl enable mysqld
        systemctl start mysqld
        systemctl status mysqld
        # filter message that contains temp password
        tmpPasswdMsg=$(grep 'temporary password' /var/log/mysqld.log)
        # split from last space, get temp password
        tmpPasswd="${tmpPasswdMsg##* }"
        echo "get mysql initial password: $tmpPasswd"
        cp $APP_HOME/sql/init-mysql.sql $APP_HOME/sql/.init-mysql.sql
        sed -i "s|@MYSQL_ROOT_PASSWORD@|$MYSQL_ROOT_PASSWORD|g" "$APP_HOME/sql/.init-mysql.sql"
        # -h must be "localhost", not host IP!
        mysql -hlocalhost -uroot -p"$tmpPasswd" -s --prompt=nowarning --connect-expired-password <"$APP_HOME/sql/.init-mysql.sql"
    fi
}

installMySqlCliIfNotExists() {
    mysql -V &>/dev/null
    if [ ! "$?" = "0" ]; then
        printHeading "INSTALL MYSQL CLI CLIENT FOR CONNECTIVITY TESTING"
        echo "MySQL client has not been installed yet, will install right now!"
        yum -y install mysql-community-server
        if [ ! -f /tmp/mysql57-community-release-el7-11.noarch.rpm ]; then
            wget https://dev.mysql.com/get/mysql57-community-release-el7-11.noarch.rpm -P /tmp/
        fi
        rpm -ivh /tmp/mysql57-community-release-el7-11.noarch.rpm
        yum -y install mysql-community-client
    fi
}

testMySqlConnectivity() {
    printHeading "TEST MYSQL CONNECTIVITY"
    installMySqlCliIfNotExists
    mysql -h$MYSQL_HOST -uroot -p$MYSQL_ROOT_PASSWORD -e "select 1;" &>/dev/null
    if [ "$?" = "0" ]; then
        echo "Connecting to mysql server is SUCCESSFUL!!"
    else
        echo "Connecting to mysql server is FAILED!!"
        exit 1
    fi
}

installMySqlJdbcDriverIfNotExists() {
    if [ ! -f /usr/share/java/mysql-connector-java.jar ]; then
        printHeading "INSTALL MYSQL JDBC DRIVER"
        wget https://dev.mysql.com/get/Downloads/Connector-J/mysql-connector-java-5.1.48.tar.gz -P /tmp/
        tar -zxvf /tmp/mysql-connector-java-5.1.48.tar.gz -C /tmp &>/dev/null
        mkdir -p /usr/share/java/
        cp /tmp/mysql-connector-java-5.1.48/mysql-connector-java-5.1.48-bin.jar /usr/share/java/mysql-connector-java.jar
        echo "Mysql JDBC Driver is installed!"
    fi
}

# ------------------------------------------------   Solr Operations   ----------------------------------------------- #

installSolrIfNotExists() {
    if [ ! -f /etc/init.d/solr ]; then
        printHeading "INSTALL SOLR"
        wget https://archive.apache.org/dist/lucene/solr/8.6.2/solr-8.6.2.tgz -P /tmp/
        tar -zxvf /tmp/solr-8.6.2.tgz -C /tmp &>/dev/null
        # install but do NOT star solr
        /tmp/solr-8.6.2/bin/install_solr_service.sh /tmp/solr-8.6.2.tgz -n
    fi
}

initSolrAsRangerAuditStore() {
    printHeading "INIT SOLR AS RANGER AUDIT STORE"
    tar -zxvf /tmp/ranger-repo/ranger-$RANGER_VERSION-solr_for_audit_setup.tar.gz -C /tmp &>/dev/null
    confFile=/tmp/solr_for_audit_setup/install.properties
    # backup confFile
    cp $confFile $confFile.$(date +%s)
    cp $APP_HOME/conf/ranger-audit/solr-template.properties $confFile
    sed -i "s|@JAVA_HOME@|$JAVA_HOME|g" $confFile
    curDir=$(pwd)
    # must run under project root dir.
    cd /tmp/solr_for_audit_setup
    sh setup.sh
    cd $curDir
    # stop first in case it is already started.
    sudo -u solr /opt/solr/ranger_audit_server/scripts/stop_solr.sh || true
    sudo -u solr /opt/solr/ranger_audit_server/scripts/start_solr.sh
    # waiting for staring, this is required!
    sleep $RESTART_INTERVAL
}

testSolrConnectivity() {
    printHeading "TEST SOLR CONNECTIVITY"
    installNcIfNotExists
    nc -vz $SOLR_HOST 8983
    if [ "$?" = "0" ]; then
        echo "Connecting to solr server is SUCCESSFUL!!"
    else
        echo "Connecting to solr server is FAILED!!"
        exit 1
    fi
}

# --------------------------------------------   Ranger-Admin Operations   ------------------------------------------- #

initRangerAdminDb() {
    printHeading "INIT RANGER DB"
    cp $APP_HOME/sql/init-ranger-db.sql $APP_HOME/sql/.init-ranger-db.sql
    sed -i "s|@DB_HOST@|$MYSQL_HOST|g" $APP_HOME/sql/.init-ranger-db.sql
    sed -i "s|@MYSQL_RANGER_DB_USER_PASSWORD@|$MYSQL_RANGER_DB_USER_PASSWORD|g" $APP_HOME/sql/.init-ranger-db.sql
    mysql -h$MYSQL_HOST -uroot -p$MYSQL_ROOT_PASSWORD -s --prompt=nowarning --connect-expired-password <$APP_HOME/sql/.init-ranger-db.sql
}

makeRangerAdminInstallPropForAd() {
    confFile="$1"
    cp $APP_HOME/conf/ranger-admin/ad-template.properties $confFile
    sed -i "s|@DB_HOST@|$MYSQL_HOST|g" $confFile
    sed -i "s|@DB_ROOT_PASSWORD@|$MYSQL_ROOT_PASSWORD|g" $confFile
    sed -i "s|@SOLR_HOST@|$SOLR_HOST|g" $confFile
    sed -i "s|@DB_PASSWORD@|$MYSQL_RANGER_DB_USER_PASSWORD|g" $confFile
    sed -i "s|@AD_DOMAIN@|$AD_DOMAIN|g" $confFile
    sed -i "s|@AD_URL@|$AD_URL|g" $confFile
    sed -i "s|@AD_BASE_DN@|$AD_BASE_DN|g" $confFile
    sed -i "s|@AD_BIND_DN@|$AD_BIND_DN|g" $confFile
    sed -i "s|@AD_BIND_PASSWORD@|$AD_BIND_PASSWORD|g" $confFile
    sed -i "s|@AD_USER_OBJECT_CLASS@|$AD_USER_OBJECT_CLASS|g" $confFile
}

makeRangerAdminInstallPropForLdap() {
    confFile="$1"
    cp $APP_HOME/conf/ranger-admin/ldap-template.properties $confFile
    sed -i "s|@DB_HOST@|$MYSQL_HOST|g" $confFile
    sed -i "s|@DB_ROOT_PASSWORD@|$MYSQL_ROOT_PASSWORD|g" $confFile
    sed -i "s|@SOLR_HOST@|$SOLR_HOST|g" $confFile
    sed -i "s|@DB_PASSWORD@|$MYSQL_RANGER_DB_USER_PASSWORD|g" $confFile
    sed -i "s|@LDAP_URL@|$LDAP_URL|g" $confFile
    sed -i "s|@LDAP_USER_DN_PATTERN@|$LDAP_USER_DN_PATTERN|g" $confFile
    sed -i "s|@LDAP_GROUP_SEARCH_FILTER@|$LDAP_GROUP_SEARCH_FILTER|g" $confFile
    sed -i "s|@LDAP_BASE_DN@|$LDAP_BASE_DN|g" $confFile
    sed -i "s|@LDAP_BIND_DN@|$LDAP_BIND_DN|g" $confFile
    sed -i "s|@LDAP_BIND_PASSWORD@|$LDAP_BIND_PASSWORD|g" $confFile
    sed -i "s|@LDAP_USER_OBJECT_CLASS@|$LDAP_USER_OBJECT_CLASS|g" $confFile
}

installRangerAdmin() {
    printHeading "INSTALL RANGER ADMIN FOR AD"
    tar -zxvf /tmp/ranger-repo/ranger-$RANGER_VERSION-admin.tar.gz -C /opt/ &>/dev/null
    installHome=/opt/ranger-$RANGER_VERSION-admin
    confFile=$installHome/install.properties
    # backup install.properties
    cp $confFile $confFile.$(date +%s)
    if [ "$AUTH_TYPE" = "ad" ]; then
        makeRangerAdminInstallPropForAd $confFile
    elif [ "$AUTH_TYPE" = "ldap" ]; then
        makeRangerAdminInstallPropForLdap $confFile
    else
        echo "Invalid authentication type, only AD and LDAP are supported!"
        exit 1
    fi
    curDir=$(pwd)
    # must run under project root dir.
    cd $installHome
    export JAVA_HOME=$JAVA_HOME
    sh setup.sh
    sh set_globals.sh
    cd $curDir
    installXmlstarletIfNotExists
    # Ranger installation scripts have BUG!!
    # although, for the sake of security, ranger write password to a key store file,
    # however, it does not work, and at the same time, it removes password in xml conf file with "_",
    # so, it can't login after installation! here, write password back to conf xml file!!
    adminConfFile=/etc/ranger/admin/conf/ranger-admin-site.xml
    cp $adminConfFile $adminConfFile.$(date +%s)
    xmlstarlet edit -L -u "/configuration/property/name[.='ranger.jpa.jdbc.password']/../value" -v "$MYSQL_RANGER_DB_USER_PASSWORD" $adminConfFile
    ranger-admin stop || true
    sleep $RESTART_INTERVAL
    ranger-admin start
    # waiting for staring, this is required!
    sleep $RESTART_INTERVAL
}

testRangerConnectivity() {
    printHeading "TEST RANGER CONNECTIVITY"
    installNcIfNotExists
    nc -vz $RANGER_HOST 6080
    if [ "$?" = "0" ]; then
        echo "Connecting to ranger server is SUCCESSFUL!!"
    else
        echo "Connecting to ranger server is FAILED!!"
        exit 1
    fi
}

# ------------------------------------------   Ranger-UserSync Operations   ------------------------------------------ #

makeRangerUsersyncInstallPropForAd() {
    confFile="$1"
    cp $APP_HOME/conf/ranger-usersync/ad-template.properties $confFile
    sed -i "s|@AD_URL@|$AD_URL|g" $confFile
    sed -i "s|@AD_BASE_DN@|$AD_BASE_DN|g" $confFile
    sed -i "s|@AD_BIND_DN@|$AD_BIND_DN|g" $confFile
    sed -i "s|@AD_BIND_PASSWORD@|$AD_BIND_PASSWORD|g" $confFile
    sed -i "s|@AD_USER_OBJECT_CLASS@|$AD_USER_OBJECT_CLASS|g" $confFile
}

makeRangerUsersyncInstallPropForLdap() {
    confFile="$1"
    cp $APP_HOME/conf/ranger-usersync/ldap-template.properties $confFile
    sed -i "s|@LDAP_URL@|$LDAP_URL|g" $confFile
    sed -i "s|@LDAP_BASE_DN@|$LDAP_BASE_DN|g" $confFile
    sed -i "s|@LDAP_BIND_DN@|$LDAP_BIND_DN|g" $confFile
    sed -i "s|@LDAP_BIND_PASSWORD@|$LDAP_BIND_PASSWORD|g" $confFile
    sed -i "s|@LDAP_USER_OBJECT_CLASS@|$LDAP_USER_OBJECT_CLASS|g" $confFile
}

installRangerUsersync() {
    printHeading "INSTALL RANGER USERSYNC FOR AD"
    tar -zxvf /tmp/ranger-repo/ranger-$RANGER_VERSION-usersync.tar.gz -C /opt/ &>/dev/null
    installHome=/opt/ranger-$RANGER_VERSION-usersync
    confFile=$installHome/install.properties
    # backup install.properties
    cp $confFile $confFile.$(date +%s)
    if [ "$AUTH_TYPE" = "ad" ]; then
        makeRangerUsersyncInstallPropForAd $confFile
    elif [ "$AUTH_TYPE" = "ldap" ]; then
        makeRangerUsersyncInstallPropForLdap $confFile
    else
        echo "Invalid authentication type, only AD and LDAP are supported!"
        exit 1
    fi
    curDir=$(pwd)
    # must run under project root dir.
    cd $installHome
    export JAVA_HOME=$JAVA_HOME
    sh setup.sh
    sh set_globals.sh
    cd $curDir
    # IMPORTANT! must enable usersync in ranger-ugsync-site.xml, by default, it is disabled!
    ugsyncConfFile=/etc/ranger/usersync/conf/ranger-ugsync-site.xml
    cp $ugsyncConfFile $ugsyncConfFile.$(date +%s)
    installXmlstarletIfNotExists
    xmlstarlet edit -L -u "/configuration/property/name[.='ranger.usersync.enabled']/../value" -v "true" $ugsyncConfFile
    ranger-usersync restart
}

# -------------------------------------------   Ranger Plugin Operations   ------------------------------------------- #

downloadRanger() {
    # repo dir plays a download flag file, if exists, skip download again.
    if [ ! -d /tmp/ranger-repo ]; then
        printHeading "DOWNLOAD RANGER"
        wget --recursive --no-parent --no-directories --no-host-directories $RANGER_REPO_URL -P /tmp/ranger-repo
    fi
}

# Because of file size limiting (<100MB) of GitHub, ranger installation files are splitted to 10 files,
# So have to combine them before unpackage
downloadRangerFromGithub() {
    # README.md play a download flag file, if exists, skip download again.
    # Too many downloads from an IP will be blocked by GitHub!
    if [ ! -f /tmp/ranger-repo/README.md ]; then
        printHeading "DOWNLOAD RANGER"
        wget https://github.com/bluishglc/ranger-repo/archive/v$RANGER_VERSION.tar.gz -O /tmp/ranger-repo.tar.gz
        tar -zxvf /tmp/ranger-repo.tar.gz -C /tmp &>/dev/null
        cat /tmp/ranger-repo/ranger-repo.tar.gz.* >/tmp/ranger-repo/ranger-repo.tar.gz
        tar -zxvf /tmp/ranger-repo/ranger-repo.tar.gz -C /tmp &>/dev/null
        rm -rf /tmp/ranger-repo.tar.gz
        rm -rf /tmp/ranger-repo/ranger-repo.tar.gz*
    fi
}

testEmrSshConnectivity() {
    printHeading "TEST EMR SSH CONNECTIVITY"
    if [ -f $EMR_SSH_KEY ]; then
        chmod 600 $EMR_SSH_KEY
        for masterNode in "${EMR_MASTER_NODES[@]}"; do
            printHeading "MASTER NODE [ $masterNode ]"
            ssh -o ConnectTimeout=5 -o ConnectionAttempts=1 -o StrictHostKeyChecking=no -i $EMR_SSH_KEY -T hadoop@$masterNode <<EOF
            systemctl --type=service --state=running|egrep '^(hadoop|hbase|hive|spark|hue|presto|oozie|zookeeper|flink)\S*'
EOF
            if [ ! "$?" = "0" ]; then
                echo "ERROR!! connection to [ $masterNode ] failed!"
                exit 1
            fi
        done
        for coreNode in "${EMR_CORE_NODES[@]}"; do
            printHeading "CORE NODE [ $coreNode ]"
            ssh -o ConnectTimeout=5 -o ConnectionAttempts=1 -o StrictHostKeyChecking=no -i $EMR_SSH_KEY -T hadoop@$coreNode <<EOF
            systemctl --type=service --state=running|egrep '^(hadoop|hbase|hive|spark|hue|presto|oozie|zookeeper|flink)\S*'
EOF
            if [ ! "$?" = "0" ]; then
                echo "ERROR!! connection to [ $coreNode ] failed!"
                exit 1
            fi
        done
    else
        echo "ERROR!! The ssh key file to login EMR nodes dese NOT exist!"
        exit 1
    fi
}

testEmrNamenodeConnectivity() {
    printHeading "TEST NAMENODE CONNECTIVITY"
    installNcIfNotExists
    for node in "${EMR_MASTER_NODES[@]}"; do
        nc -vz $node 8020 &>/dev/null
        if [ "$?" = "0" ]; then
            echo "Connecting to namenode [ $node ] is SUCCESSFUL!!"
        else
            echo "Connecting to namenode [ $node ] is FAILED!!"
            exit 1
        fi
    done
}

testSolrConnectivityFromEmrNodes() {
    printHeading "TEST CONNECTIVITY FROM EMR NODES TO SOLR"
    for node in "${EMR_NODES[@]}"; do
        ssh -o StrictHostKeyChecking=no -i $EMR_SSH_KEY -T hadoop@$node <<EOF
        if ! nc --version &>/dev/null; then
            sudo yum -y install nc
        fi
EOF
        ssh -o StrictHostKeyChecking=no -i $EMR_SSH_KEY -T hadoop@$node nc -vz $SOLR_HOST 8983
        if [ "$?" = "0" ]; then
            echo "Connecting to solr server from [ $node ] is SUCCESSFUL!!"
        else
            echo "Connecting to solr server from [ $node ] is FAILED!!"
            exit 1
        fi
    done
}

testRangerConnectivityFromEmrNodes() {
    printHeading "TEST CONNECTIVITY FROM EMR NODES TO RANGER"
    for node in "${EMR_NODES[@]}"; do
        ssh -o StrictHostKeyChecking=no -i $EMR_SSH_KEY -T hadoop@$node <<EOF
        if ! nc --version &>/dev/null; then
            sudo yum -y install nc
        fi
EOF
        ssh -o StrictHostKeyChecking=no -i $EMR_SSH_KEY -T hadoop@$node nc -vz $RANGER_HOST 6080
        if [ "$?" = "0" ]; then
            echo "Connecting to ranger server from [ $node ] is SUCCESSFUL!!"
        else
            echo "Connecting to ranger server from [ $node ] is FAILED!!"
            exit 1
        fi
    done
}

getEmrClusterId() {
    ssh -o StrictHostKeyChecking=no -i $EMR_SSH_KEY -T hadoop@${EMR_MASTER_NODES[0]} sudo jq -r .jobFlowId /mnt/var/lib/info/job-flow.json
}

installRangerPlugins() {
    for plugin in "${RANGER_PLUGINS[@]}"; do
        case $plugin in
        hdfs)
            installRangerHdfsPlugin
            ;;
        hive)
            installRangerHivePlugin
            ;;
        hbase)
            installRangerHBasePlugin
            ;;
        *)
            echo "ERROR!! No [$plugin] plugin or it is not supported by this tool yet."
            ;;
        esac
    done
}

initRangerHdfsRepo() {
    printHeading "INIT RANGER HDFS REPO"
    cp $APP_HOME/policy/hdfs-repo.json $APP_HOME/policy/.hdfs-repo.json
    sed -i "s|@EMR_CLUSTER_ID@|$(getEmrClusterId)|g" $APP_HOME/policy/.hdfs-repo.json
    sed -i "s|@EMR_HDFS_URL@|$EMR_HDFS_URL|g" $APP_HOME/policy/.hdfs-repo.json
    curl -iv -u admin:admin -d @$APP_HOME/policy/.hdfs-repo.json -H "Content-Type: application/json" \
        -X POST http://$RANGER_HOST:6080/service/public/api/repository/
    sleep 5 # sleep for a while, otherwise repo may be not available for policy to refer.
    # import user default policy is required, otherwise some services have no permission to r/w its data, i.e. hbase
    cp $APP_HOME/policy/hdfs-policy.json $APP_HOME/policy/.hdfs-policy.json
    sed -i "s|@EMR_CLUSTER_ID@|$(getEmrClusterId)|g" $APP_HOME/policy/.hdfs-policy.json
    curl -iv -u admin:admin -d @$APP_HOME/policy/.hdfs-policy.json -H "Content-Type: application/json" \
        -X POST http://$RANGER_HOST:6080/service/public/api/policy/
    echo ""
}

initRangerHiveRepo() {
    printHeading "INIT RANGER HIVE REPO"
    cp $APP_HOME/policy/hive-repo.json $APP_HOME/policy/.hive-repo.json
    sed -i "s|@EMR_CLUSTER_ID@|$(getEmrClusterId)|g" $APP_HOME/policy/.hive-repo.json
    sed -i "s|@EMR_HIVE_SERVER2@|$EMR_HIVE_SERVER2|g" $APP_HOME/policy/.hive-repo.json
    curl -iv -u admin:admin -d @$APP_HOME/policy/.hive-repo.json -H "Content-Type: application/json" \
        -X POST http://$RANGER_HOST:6080/service/public/api/repository/
    echo ""
}

initRangerHbaseRepo() {
    printHeading "INIT RANGER HBASE REPO"
    cp $APP_HOME/policy/hbase-repo.json $APP_HOME/policy/.hbase-repo.json
    sed -i "s|@EMR_CLUSTER_ID@|$(getEmrClusterId)|g" $APP_HOME/policy/.hbase-repo.json
    sed -i "s|@EMR_ZK_QUORUM@|$EMR_ZK_QUORUM|g" $APP_HOME/policy/.hbase-repo.json
    curl -iv -u admin:admin -d @$APP_HOME/policy/.hbase-repo.json -H "Content-Type: application/json" \
        -X POST http://$RANGER_HOST:6080/service/public/api/repository/
    echo ""
}

installRangerHdfsPlugin() {
    # Must init repo first before install plugin
    initRangerHdfsRepo
    printHeading "INSTALL RANGER HDFS PLUGIN"
    tar -zxvf /tmp/ranger-repo/ranger-$RANGER_VERSION-hdfs-plugin.tar.gz -C /tmp &>/dev/null
    installFilesDir=/tmp/ranger-$RANGER_VERSION-hdfs-plugin
    confFile=$installFilesDir/install.properties
    # backup install.properties
    cp $confFile $confFile.$(date +%s)
    cp $APP_HOME/conf/ranger-plugin/hdfs-template.properties $confFile
    sed -i "s|@EMR_CLUSTER_ID@|$(getEmrClusterId)|g" $confFile
    sed -i "s|@SOLR_HOST@|$SOLR_HOST|g" $confFile
    sed -i "s|@RANGER_HOST@|$RANGER_HOST|g" $confFile
    installHome=/opt/ranger-$RANGER_VERSION-hdfs-plugin
    for masterNode in "${EMR_MASTER_NODES[@]}"; do
        printHeading "INSTALL RANGER HDFS PLUGIN ON MASTER NODE [ $masterNode ]: "
        ssh -o StrictHostKeyChecking=no -i $EMR_SSH_KEY -T hadoop@$masterNode sudo rm -rf $installFilesDir $installHome
        # NOTE: we can't copy files from local /tmp/plugin-dir to remote /opt/plugin-dir,
        # because hadoop user has no write permission at /opt
        scp -o StrictHostKeyChecking=no -i $EMR_SSH_KEY -r $installFilesDir hadoop@$masterNode:$installFilesDir &>/dev/null
        ssh -o StrictHostKeyChecking=no -i $EMR_SSH_KEY -T hadoop@$masterNode <<EOF
            sudo cp -r $installFilesDir $installHome
            # the enable-hdfs-plugin.sh just work with open source version of hadoop,
            # for emr, we have to copy ranger jars to /usr/lib/hadoop-hdfs/lib/
            sudo find $installHome/lib -name *.jar -exec cp {} /usr/lib/hadoop-hdfs/lib/ \;
            sudo sh $installHome/enable-hdfs-plugin.sh
EOF
    done
    restartNamenode
}

restartNamenode() {
    printHeading "RESTART NAMENODE"
    for masterNode in "${EMR_MASTER_NODES[@]}"; do
        echo "STOP NAMENODE ON MASTER NODE [ $masterNode ]"
        ssh -o StrictHostKeyChecking=no -i $EMR_SSH_KEY -T hadoop@$masterNode sudo systemctl stop hadoop-hdfs-namenode
        sleep $RESTART_INTERVAL
        echo "START NAMENODE ON MASTER NODE [ $masterNode ]"
        ssh -o StrictHostKeyChecking=no -i $EMR_SSH_KEY -T hadoop@$masterNode sudo systemctl start hadoop-hdfs-namenode
        sleep $RESTART_INTERVAL
    done
}

installRangerHivePlugin() {
    # Must init repo first before install plugin
    initRangerHiveRepo
    printHeading "INSTALL RANGER HIVE PLUGIN"
    tar -zxvf /tmp/ranger-repo/ranger-$RANGER_VERSION-hive-plugin.tar.gz -C /tmp/ &>/dev/null
    installFilesDir=/tmp/ranger-$RANGER_VERSION-hive-plugin
    confFile=$installFilesDir/install.properties
    # backup install.properties
    cp $confFile $confFile.$(date +%s)
    cp $APP_HOME/conf/ranger-plugin/hive-template.properties $confFile
    sed -i "s|@EMR_CLUSTER_ID@|$(getEmrClusterId)|g" $confFile
    sed -i "s|@SOLR_HOST@|$SOLR_HOST|g" $confFile
    sed -i "s|@RANGER_HOST@|$RANGER_HOST|g" $confFile
    installHome=/opt/ranger-$RANGER_VERSION-hive-plugin
    for masterNode in "${EMR_MASTER_NODES[@]}"; do
        printHeading "INSTALL RANGER HIVE PLUGIN ON MASTER NODE [ $masterNode ] "
        ssh -o StrictHostKeyChecking=no -i $EMR_SSH_KEY -T hadoop@$masterNode sudo rm -rf $installFilesDir $installHome
        # NOTE: we can't copy files from local /tmp/plugin-dir to remote /opt/plugin-dir,
        # because hadoop user has no write permission at /opt
        scp -o StrictHostKeyChecking=no -i $EMR_SSH_KEY -r $installFilesDir hadoop@$masterNode:$installFilesDir &>/dev/null
        ssh -o StrictHostKeyChecking=no -i $EMR_SSH_KEY -T hadoop@$masterNode <<EOF
            sudo cp -r $installFilesDir $installHome
            # the enable-hive-plugin.sh just work with open source version of hadoop,
            # for emr, we have to copy ranger jars to /usr/lib/hive/lib/
            sudo find $installHome/lib -name *.jar -exec cp {} /usr/lib/hive/lib/ \;
            sudo sh $installHome/enable-hive-plugin.sh
EOF
    done
    restartHiveServer2
}

restartHiveServer2() {
    printHeading "RESTART HIVESERVER2"
    for masterNode in "${EMR_MASTER_NODES[@]}"; do
        echo "STOP HIVESERVER2 ON MASTER NODE [ $masterNode ]"
        ssh -o StrictHostKeyChecking=no -i $EMR_SSH_KEY -T hadoop@$masterNode sudo systemctl stop hive-server2
        sleep $RESTART_INTERVAL
        echo "START HIVESERVER2 ON MASTER NODE [ $masterNode ]"
        ssh -o StrictHostKeyChecking=no -i $EMR_SSH_KEY -T hadoop@$masterNode sudo systemctl start hive-server2
        sleep $RESTART_INTERVAL
    done
}

installRangerHBasePlugin() {
    # Must init repo first before install plugin
    initRangerHbaseRepo
    printHeading "INSTALL RANGER HBASE PLUGIN"
    tar -zxvf /tmp/ranger-repo/ranger-$RANGER_VERSION-hbase-plugin.tar.gz -C /tmp &>/dev/null
    installFilesDir=/tmp/ranger-$RANGER_VERSION-hbase-plugin
    confFile=$installFilesDir/install.properties
    # backup install.properties
    cp $confFile $confFile.$(date +%s)
    cp $APP_HOME/conf/ranger-plugin/hbase-template.properties $confFile
    sed -i "s|@EMR_CLUSTER_ID@|$(getEmrClusterId)|g" $confFile
    sed -i "s|@SOLR_HOST@|$SOLR_HOST|g" $confFile
    sed -i "s|@RANGER_HOST@|$RANGER_HOST|g" $confFile
    for node in "${EMR_NODES[@]}"; do
        printHeading "INSTALL RANGER HBASE PLUGIN ON NODE [ $masterNode ]"
        installHome=/opt/ranger-$RANGER_VERSION-hbase-plugin
        ssh -o StrictHostKeyChecking=no -i $EMR_SSH_KEY -T hadoop@$node sudo rm -rf $installFilesDir $installHome
        # NOTE: we can't copy files from local /tmp/plugin-dir to remote /opt/plugin-dir,
        # because hadoop user has no write permission at /opt
        scp -o StrictHostKeyChecking=no -i $EMR_SSH_KEY -r $installFilesDir hadoop@$node:$installFilesDir &>/dev/null
        ssh -o StrictHostKeyChecking=no -i $EMR_SSH_KEY -T hadoop@$node <<EOF
        sudo cp -r $installFilesDir $installHome
        # the enable-hbase-plugin.sh just work with open source version of hadoop,
        # for emr, we have to copy ranger jars to /usr/lib/hbase/lib/
        sudo find $installHome/lib -name *.jar -exec cp {} /usr/lib/hbase/lib/ \;
        sudo sh $installHome/enable-hbase-plugin.sh
EOF
    done
    restartHbase
}

restartHbase() {
    printHeading "RESTART HBASE"
    for node in "${EMR_MASTER_NODES[@]}"; do
        echo "STOP HBASE-MASTER ON MASTER NODE [ $node ]"
        ssh -o StrictHostKeyChecking=no -i $EMR_SSH_KEY -T hadoop@$node sudo systemctl stop hbase-master
        sleep $RESTART_INTERVAL
        echo "START HBASE-MASTER ON MASTER NODE [ $node ]"
        ssh -o StrictHostKeyChecking=no -i $EMR_SSH_KEY -T hadoop@$node sudo systemctl start hbase-master
        sleep $RESTART_INTERVAL
    done
    # stop regionserver first, then master
    for node in "${EMR_CORE_NODES[@]}"; do
        echo "RESTART HBASE-REGIONSERVER ON CORE NODE [ $node ]"
        # Get remote hostname (just hostname, not fqdn, only this value can trigger graceful_stop.sh work with hbase-daemon.sh
        # not hbase-daemons.sh, EMR has no this file.
        remoteHostname=$(ssh -o StrictHostKeyChecking=no -i $EMR_SSH_KEY -T hadoop@$node hostname)
        ssh -o StrictHostKeyChecking=no -i $EMR_SSH_KEY -T hadoop@$node sudo -u hbase /usr/lib/hbase/bin/graceful_stop.sh --restart --reload $remoteHostname &>/dev/null
        sleep $RESTART_INTERVAL
    done
}

# -----------------------------------------------   Utils Operations   ----------------------------------------------- #

installXmlstarletIfNotExists() {
    if ! xmlstarlet --version &>/dev/null; then
        yum -y install https://dl.fedoraproject.org/pub/epel/epel-release-latest-$(rpm -E '%{rhel}').noarch.rpm &>/dev/null
        yum -y install xmlstarlet &>/dev/null
    fi
}

installNcIfNotExists() {
    if ! nc --version &>/dev/null; then
        yum -y install nc &>/dev/null
    fi
}
