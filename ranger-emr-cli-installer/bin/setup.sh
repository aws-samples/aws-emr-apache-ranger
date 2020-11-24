#!/bin/sh

# Run the below commands as root
if [ "$(whoami)" != "root" ]; then
    echo "Run me as [ root ] user!"
    exit 1
fi

APP_HOME="$(
    cd "$(dirname $(readlink -nf "$0"))"/..
    pwd -P
)"

DEFAULT_RANGER_REPO_URL='http://52.81.173.97:7080/ranger-repo/'
DEFAULT_JAVA_HOME='/usr/lib/jvm/java'
DEFAULT_DB_PASSWORD='Admin1234!'
DEFAULT_HOSTNAME=$(hostname -i)
DEFAULT_RANGER_VERSION='2.1.0'
DEFAULT_RESTART_INTERVAL=30

OPT_KEYS=(
    AUTH_TYPE
    AD_DOMAIN AD_URL AD_BASE_DN AD_BIND_DN AD_BIND_PASSWORD AD_USER_OBJECT_CLASS
    LDAP_URL LDAP_USER_DN_PATTERN LDAP_GROUP_SEARCH_FILTER LDAP_BASE_DN LDAP_BIND_DN LDAP_BIND_PASSWORD LDAP_USER_OBJECT_CLASS
    JAVA_HOME SKIP_INSTALL_MYSQL MYSQL_HOST MYSQL_ROOT_PASSWORD MYSQL_RANGER_DB_USER_PASSWORD
    SKIP_INSTALL_SOLR SOLR_HOST RANGER_REPO_URL RANGER_VERSION RANGER_PLUGINS
    EMR_NODES EMR_MASTER_NODES EMR_CORE_NODES EMR_HDFS_URL EMR_ZK_QUORUM EMR_HIVE_SERVER2 EMR_SSH_KEY RESTART_INTERVAL
)

source "$APP_HOME/bin/utils.sh"
source "$APP_HOME/bin/funcs.sh"

resetConfigs
parseArgs "$@"
printConfigs

# ----------------------------------------------    Scripts Entrance    ---------------------------------------------- #

case $1 in
install)
    shift
    testEmrSshConnectivity
    testEmrNamenodeConnectivity
    testLdapConnectivity
    if [ "$SKIP_INSTALL_MYSQL" = "false" ]; then
        installMySqlIfNotExists
    fi
    testMySqlConnectivity
    installMySqlJdbcDriverIfNotExists
    installJdk8IfNotExists
    downloadRanger
    # If skip installing solr, please perform initSolrAsRangerAuditStore
    # operation on remote solr server mannually! this is required!
    if [ "$SKIP_INSTALL_SOLR" = "false" ]; then
        installSolrIfNotExists
        initSolrAsRangerAuditStore
    fi
    testSolrConnectivity
    initRangerAdminDb
    installRangerAdmin
    testRangerConnectivity
    installRangerUsersync
    testSolrConnectivityFromEmrNodes
    testRangerConnectivityFromEmrNodes
    installRangerPlugins
    printHeading "ALL DONE!!"
    ;;
install-ranger)
    shift
    printHeading "STARTING SETUP!!"
    testLdapConnectivity
    if [ "$SKIP_INSTALL_MYSQL" = "false" ]; then
        installMySqlIfNotExists
    fi
    testMySqlConnectivity
    installMySqlJdbcDriverIfNotExists
    installJdk8IfNotExists
    downloadRanger
    # If skip installing solr, please perform initSolrAsRangerAuditStore
    # operation on remote solr server mannually! this is required!
    if [ "$SKIP_INSTALL_SOLR" = "false" ]; then
        installSolrIfNotExists
        initSolrAsRangerAuditStore
    fi
    testSolrConnectivity
    initRangerAdminDb
    installRangerAdmin
    testRangerConnectivity
    installRangerUsersync
    printHeading "ALL DONE!!"
    ;;
install-ranger-plugins)
    shift
    testEmrSshConnectivity
    testEmrNamenodeConnectivity
    testSolrConnectivityFromEmrNodes
    testRangerConnectivityFromEmrNodes
    installRangerPlugins
    printHeading "ALL DONE!!"
    ;;
test-emr-ssh-connectivity)
    shift
    testEmrSshConnectivity
    ;;
test-emr-namenode-connectivity)
    shift
    testEmrNamenodeConnectivity
    ;;
test-ldap-connectivity)
    shift
    testLdapConnectivity
    ;;
install-mysql)
    shift
    installMySqlIfNotExists
    ;;
test-mysql-connectivity)
    shift
    testMySqlConnectivity
    ;;
install-mysql-jdbc-driver)
    installMySqlJdbcDriverIfNotExists
    ;;
install-jdk)
    shift
    installJdk8IfNotExists
    ;;
download-ranger)
    shift
    downloadRanger
    ;;
install-solr)
    shift
    installSolrIfNotExists
    ;;
test-solr-connectivity)
    shift
    testSolrConnectivity
    ;;
init-solr-as-ranger-audit-store)
    shift
    initSolrAsRangerAuditStore
    ;;
init-ranger-admin-db)
    shift
    initRangerAdminDb
    ;;
install-ranger-admin)
    shift
    initRangerAdminDb
    installRangerAdmin
    ;;
install-ranger-usersync)
    shift
    installRangerUsersync
    ;;
help)
    shift
    printUsage
    ;;
*)
    shift
    printUsage
    ;;
esac

