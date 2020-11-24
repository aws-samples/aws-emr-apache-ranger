#!/usr/bin/env bash

parseArgs() {
    if [ "$#" -eq 0 ]; then
        printUsage
        exit 0
    fi
    optString="ranger-host:,auth-type:,ad-domain:,ad-url:,ad-base-dn:,ad-bind-dn:,ad-bind-password:,ad-user-object-class:,\
    ldap-url:,ldap-user-dn-pattern:,ldap-group-search-filter:,ldap-base-dn:,ldap-bind-dn:,ldap-bind-password:,ldap-user-object-class:,\
    java-home:,skip-install-mysql:,mysql-host:,mysql-root-password:,mysql-ranger-db-user-password:,\
    skip-install-solr:,solr-host:,ranger-version:,ranger-repo-url:,restart-interval:,\
    ranger-plugins:,emr-master-nodes:,emr-core-nodes:,emr-ssh-key:"
    # IMPORTANT!! -o option can not be omitted, even there are no any short options!
    # otherwise, parsing will go wrong!
    OPTS=$(getopt -o "" -l "$optString" -- "$@")
    exitCode=$?
    if [ $exitCode -ne 0 ]; then
        echo ""
        printUsage
        exit 1
    fi
    eval set -- "$OPTS"
    while true; do
        case "$1" in
            --auth-type)
                AUTH_TYPE="${2,,}"
                shift 2
                ;;
            --ad-domain)
                AD_DOMAIN="$2"
                shift 2
                ;;
            --ad-url)
                AD_URL="$2"
                shift 2
                ;;
            --ad-base-dn)
                AD_BASE_DN="$2"
                shift 2
                ;;
            --ad-bind-dn)
                AD_BIND_DN="$2"
                shift 2
                ;;
            --ad-bind-password)
                AD_BIND_PASSWORD="$2"
                shift 2
                ;;
            --ad-user-object-class)
                AD_USER_OBJECT_CLASS="$2"
                shift 2
                ;;
            --ldap-url)
                LDAP_URL="$2"
                shift 2
                ;;
            --ldap-user-dn-pattern)
                LDAP_USER_DN_PATTERN="$2"
                shift 2
                ;;
            --ldap-group-search-filter)
                LDAP_GROUP_SEARCH_FILTER="$2"
                shift 2
                ;;
            --ldap-base-dn)
                LDAP_BASE_DN="$2"
                shift 2
                ;;
            --ldap-bind-dn)
                LDAP_BIND_DN="$2"
                shift 2
                ;;
            --ldap-bind-password)
                LDAP_BIND_PASSWORD="$2"
                shift 2
                ;;
            --ldap-user-object-class)
                LDAP_USER_OBJECT_CLASS="$2"
                shift 2
                ;;
            --java-home)
                JAVA_HOME="$2"
                shift 2
                ;;
            --skip-install-mysql)
                if [ "$2" != "true" -a "$2" != "false" ]; then
                    echo "For --skip-install-mysql option, only 'true' or 'false' is valid!"
                    exit 1
                fi
                SKIP_INSTALL_MYSQL="$2"
                shift 2
                ;;
            --ranger-host)
                RANGER_HOST="$2"
                shift 2
                ;;
            --mysql-host)
                MYSQL_HOST="$2"
                shift 2
                ;;
            --mysql-root-password)
                MYSQL_ROOT_PASSWORD="$2"
                shift 2
                ;;
            --mysql-ranger-db-user-password)
                MYSQL_RANGER_DB_USER_PASSWORD="$2"
                shift 2
                ;;
            --skip-install-solr)
                if [ "$2" != "true" -a "$2" != "false" ]; then
                    echo "For --skip-install-solr option, only 'true' or 'false' is valid!"
                    exit 1
                fi
                SKIP_INSTALL_SOLR="$2"
                shift 2
                ;;
            --solr-host)
                SOLR_HOST="$2"
                shift 2
                ;;
            --ranger-version)
                RANGER_VERSION="$2"
                shift 2
                ;;
            --ranger-repo-url)
                RANGER_REPO_URL="$2"
                shift 2
                ;;
            --ranger-plugins)
                IFS=', ' read -r -a RANGER_PLUGINS <<< "${2,,}"
                shift 2
                ;;
            --emr-master-nodes)
                # remove all blank chars, EMR_ZK_QUORUM looks like 'node1,node2,node3'
                EMR_ZK_QUORUM=${2//[[:blank:]]/}
                # split comma seperated string to array, EMR_MASTER_NODES is an array
                IFS=', ' read -r -a EMR_MASTER_NODES <<< "$EMR_ZK_QUORUM"
                # add hdfs:// prefix and :8020 postfix, EMR_HDFS_URL looks like 'hdfs://node1:8020,hdfs://node2:8020,hdfs://node3:8020'
                EMR_HDFS_URL=$(echo $EMR_ZK_QUORUM | sed -E 's/([^,]+)/hdfs:\/\/\1:8020/g')
                # NOTE: ranger hive plugin will use hiveserver2 address, for single master node EMR cluster,
                # it is master node, for multi masters EMR cluster, all 3 master nodes will install hiverserver2
                # usually, there should be a virtual IP play hiverserver2 role, but EMR has no such config.
                # here, we pick first master node as hiveserver2
                EMR_HIVE_SERVER2=${EMR_MASTER_NODES[0]}
                shift 2
                ;;
            --emr-core-nodes)
                IFS=', ' read -r -a EMR_CORE_NODES <<< "$2"
                shift 2
                ;;
            --emr-ssh-key)
                EMR_SSH_KEY="$2"
                shift 2
                ;;
            --restart-interval)
                RESTART_INTERVAL="$2"
                shift 2
                ;;
            --) # No more arguments
                shift
                break
                ;;
            *)
                echo ""
                echo "Invalid option $1." >&2
                printUsage
                exit 1
                ;;
        esac
    done
    shift $((OPTIND-1))
    additionalOpts=$*
    # merge EMR_MASTER_NODES and EMR_CORE_NODES to emr EMR_NODES
    EMR_NODES=("${EMR_MASTER_NODES[@]}" "${EMR_CORE_NODES[@]}")
    if [ "$AUTH_TYPE" = "ad" ]; then
        # check if all required config items are set
        adKeys=(AD_DOMAIN AD_URL AD_BASE_DN AD_BIND_DN AD_BIND_PASSWORD)
        for key in "${adKeys[@]}"; do
            if [ "$(eval echo \$$key)" = "" ]; then
                echo "ERROR: [ $key ] is NOT set, it is required for Windows AD config."
                exit 1
            fi
        done
        if [ "$AD_USER_OBJECT_CLASS" = "" ]; then
            # set default value if not set
            AD_USER_OBJECT_CLASS="person"
        fi
    elif [ "$AUTH_TYPE" = "ldap" ]; then
        ldapKeys=(LDAP_URL LDAP_BASE_DN LDAP_BIND_DN LDAP_BIND_PASSWORD)
        for key in "${ldapKeys[@]}"; do
            if [ "$(eval echo \$$key)" = "" ]; then
                echo "ERROR: [ $key ] is NOT set, it is required for OpenLDAP config."
                exit 1
            fi
        done
        # If not set, assign default value
        if [ "$LDAP_USER_DN_PATTERN" = "" ]; then
            LDAP_USER_DN_PATTERN="uid={0},$LDAP_BASE_DN"
        fi
        if [ "$LDAP_GROUP_SEARCH_FILTER" = "" ]; then
            LDAP_GROUP_SEARCH_FILTER="(member=uid={0},$LDAP_BASE_DN)"
        fi
        if [ "$LDAP_USER_OBJECT_CLASS" = "" ]; then
            LDAP_USER_OBJECT_CLASS="inetOrgPerson"
        fi
    fi
}

resetConfigs() {
    for key in "${OPT_KEYS[@]}"; do
        eval $key=""
    done
    # Set default value for some configs if there are not set in command line.
    JAVA_HOME=$DEFAULT_JAVA_HOME
    MYSQL_HOST=$DEFAULT_HOSTNAME
    MYSQL_ROOT_PASSWORD=$DEFAULT_DB_PASSWORD
    MYSQL_RANGER_DB_USER_PASSWORD=$DEFAULT_DB_PASSWORD
    SOLR_HOST=$DEFAULT_HOSTNAME
    RANGER_REPO_URL=$DEFAULT_RANGER_REPO_URL
    RANGER_VERSION=$DEFAULT_RANGER_VERSION
    RANGER_HOST=$DEFAULT_HOSTNAME
    RESTART_INTERVAL=$DEFAULT_RESTART_INTERVAL
    SKIP_INSTALL_MYSQL=false
    SKIP_INSTALL_SOLR=false
    AD_USER_OBJECT_CLASS=""
    AD_BASE_DN=""
    AD_BIND_PASSWORD=""
    AD_DOMAIN=""
    AD_URL=""
    LDAP_USER_OBJECT_CLASS=""
    LDAP_BASE_DN=""
    LDAP_BIND_DN=""
    LDAP_BIND_PASSWORD=""
    LDAP_GROUP_SEARCH_FILTER=""
    LDAP_URL=""
    LDAP_USER_DN_PATTERN=""
    EMR_NODES=""
    EMR_MASTER_NODES=""
    EMR_CORE_NODES=""
    EMR_HDFS_URL=""
    EMR_ZK_QUORUM=""
    EMR_HIVE_SERVER2=""
    RANGER_PLUGINS=""
}

printConfigs() {
    printHeading "CONFIGURATION ITEMS"
    for key in "${OPT_KEYS[@]}"; do
        case $key in
        EMR_NODES|EMR_MASTER_NODES|EMR_CORE_NODES|RANGER_PLUGINS)
            val=$(eval echo \${${key}[@]})
            echo "$key = $val"
            ;;
        *)
            val=$(eval echo \$$key)
            echo "$key = $val"
            ;;
        esac
    done
}

validateConfigs() {
    for key in "${OPT_KEYS[@]}"; do
        val=$(eval echo \$$key)
        if [ "$val" = "" ]; then
            echo "Required config item [ $key ] is not set, installing process will exit!"
            exit 1
        fi
    done
}

printHeading()
{
    title="$1"
    if [ "$TERM" = "dumb" -o "$TERM" = "unknown" ]; then
        paddingWidth=60
    else
        paddingWidth=$((($(tput cols)-${#title})/2-5))
    fi
    printf "\n%${paddingWidth}s"|tr ' ' '='
    printf "    $title    "
    printf "%${paddingWidth}s\n\n"|tr ' ' '='
}

validateTime()
{
    if [ "$1" = "" ]
    then
        echo "Time is missing!"
        exit 1
    fi
    TIME=$1
    date -d "$TIME" >/dev/null 2>&1
    if [ "$?" != "0" ]
    then
        echo "Invalid Time: $TIME"
        exit 1
    fi
}

printUsage() {
    echo ""
    printHeading "RANGER-EMR-CLI-INSTALLER USAGE"
    echo ""
    echo "SYNOPSIS"
    echo ""
    echo "sudo sh ranger-emr-cli-installer/bin/setup.sh [ACTION] [--OPTION1 VALUE1] [--OPTION2 VALUE2]..."
    echo ""
    echo "ACTIONS:"
    echo ""
    echo "install                               Install all components"
    echo "install-ranger                        Install ranger only"
    echo "install-ranger-plugins                Install ranger plugin only"
    echo "test-emr-ssh-connectivity             Test EMR ssh connectivity"
    echo "test-emr-namenode-connectivity        Test EMR namenode connectivity"
    echo "test-ldap-connectivity                Test LDAP connectivity"
    echo "install-mysql                         Install MySQL"
    echo "test-mysql-connectivity               Test MySQL connectivity"
    echo "install-mysql-jdbc-driver             Install MySQL JDBC driver"
    echo "install-jdk                           Install JDK8"
    echo "download-ranger                       Download ranger"
    echo "install-solr                          Install solr"
    echo "test-solr-connectivity                Test solr connectivity"
    echo "init-solr-as-ranger-audit-store       Test solr connectivity"
    echo "init-ranger-admin-db                  Init ranger admin db"
    echo "install-ranger-admin                  Install ranger admin"
    echo "install-ranger-usersync               Install ranger usersync"
    echo "help                                  Print help"
    echo ""
    echo "OPTIONS:"
    echo ""
    echo "--auth-type [ad|ldap]                 Authentication type, optional value: ad or ldap"
    echo "--ad-domain                           Specify the domain name of windows ad server"
    echo "--ad-url                              Specify the ldap url of windows ad server, i.e. ldap://10.0.0.1"
    echo "--ad-base-dn                          Specify the base dn of windows ad server"
    echo "--ad-bind-dn                          Specify the bind dn of windows ad server"
    echo "--ad-bind-password                    Specify the bind password of windows ad server"
    echo "--ad-user-object-class                Specify the user object class of windows ad server"
    echo "--ldap-url                            Specify the ldap url of Open LDAP, i.e. ldap://10.0.0.1"
    echo "--ldap-user-dn-pattern                Specify the user dn pattern of Open LDAP"
    echo "--ldap-group-search-filter            Specify the group search filter of Open LDAP"
    echo "--ldap-base-dn                        Specify the base dn of Open LDAP"
    echo "--ldap-bind-dn                        Specify the bind dn of Open LDAP"
    echo "--ldap-bind-password                  Specify the bind password of Open LDAP"
    echo "--ldap-user-object-class              Specify the user object class of Open LDAP"
    echo "--java-home                           Specify the JAVA_HOME path, default value is /usr/lib/jvm/java"
    echo "--skip-install-mysql [true|false]     Specify If skip mysql installing or not, default value is 'false'"
    echo "--mysql-host                          Specify the mysql server hostname or IP, default value is current host IP"
    echo "--mysql-root-password                 Specify the root password of mysql"
    echo "--mysql-ranger-db-user-password       Specify the ranger db user password of mysql"
    echo "--solr-host                           Specify the solr server hostname or IP, default value is current host IP"
    echo "--skip-install-solr [true|false]      Specify If skip solr installing or not, default value is 'false'"
    echo "--ranger-host                         Specify the ranger server hostname or IP, default value is current host IP"
    echo "--ranger-version [2.1.0]              Specify the ranger version, now only Ranger 2.1.0 is supported"
    echo "--ranger-repo-url                     Specify the ranger repository url"
    echo "--ranger-plugins [hdfs|hive|hbase]    Specify what plugins will be installed(accept multiple comma-separated values), now support hdfs, hive and hbase"
    echo "--emr-master-nodes                    Specify master nodes list of EMR cluster(accept multiple comma-separated values), i.e. 10.0.0.1,10.0.0.2,10.0.0.3"
    echo "--emr-core-nodes                      Specify core nodes list of EMR cluster(accept multiple comma-separated values), i.e. 10.0.0.4,10.0.0.5,10.0.0.6"
    echo "--emr-ssh-key                         Specify the path of ssh key to connect EMR nodes"
    echo "--restart-interval                    Specify the restart interval"
    echo ""
    echo "SAMPLES:"
    echo ""
    echo "1. All-In-One install, install Ranger, then integrate to a Windows AD server and a multi-master EMR cluster"
    echo ""
    cat << EOF | sed 's/^ *//'
    sudo ranger-emr-cli-installer/bin/setup.sh install \\
    --ranger-host $(hostname -i) \\
    --java-home /usr/lib/jvm/java \\
    --skip-install-mysql false \\
    --mysql-host $(hostname -i) \\
    --mysql-root-password 'Admin1234!' \\
    --mysql-ranger-db-user-password 'Admin1234!' \\
    --skip-install-solr false \\
    --solr-host $(hostname -i) \\
    --auth-type ad \\
    --ad-domain corp.emr.local \\
    --ad-url ldap://10.0.0.194 \\
    --ad-base-dn 'cn=users,dc=corp,dc=emr,dc=local' \\
    --ad-bind-dn 'cn=ranger,ou=service accounts,dc=corp,dc=emr,dc=local' \\
    --ad-bind-password 'Admin1234!' \\
    --ad-user-object-class person \\
    --ranger-version 2.1.0 \\
    --ranger-repo-url 'http://52.81.173.97:7080/ranger-repo/' \\
    --ranger-plugins hdfs,hive,hbase \\
    --emr-master-nodes 10.0.0.177,10.0.0.199,10.0.0.21 \\
    --emr-core-nodes 10.0.0.114,10.0.0.136 \\
    --emr-ssh-key /home/ec2-user/key.pem \\
    --restart-interval 30
EOF
    echo ""
    echo "2. All-In-One install, install Ranger, then integrate to a Open LDAP server and a multi-master EMR cluster"
    echo ""
    cat << EOF | sed 's/^ *//'
    sudo ranger-emr-cli-installer/bin/setup.sh install \\
    --ranger-host $(hostname -i) \\
    --java-home /usr/lib/jvm/java \\
    --skip-install-mysql false \\
    --mysql-host $(hostname -i) \\
    --mysql-root-password 'Admin1234!' \\
    --mysql-ranger-db-user-password 'Admin1234!' \\
    --skip-install-solr false \\
    --solr-host $(hostname -i) \\
    --auth-type ldap \\
    --ldap-url ldap://10.0.0.41 \\
    --ldap-base-dn 'dc=example,dc=com' \\
    --ldap-bind-dn 'cn=ranger,ou=service accounts,dc=example,dc=com' \\
    --ldap-bind-password 'Admin1234!' \\
    --ldap-user-dn-pattern 'uid={0},dc=example,dc=com' \\
    --ldap-group-search-filter '(member=uid={0},dc=example,dc=com)' \\
    --ldap-user-object-class inetOrgPerson \\
    --ranger-version 2.1.0 \\
    --ranger-repo-url 'http://52.81.173.97:7080/ranger-repo/' \\
    --ranger-plugins hdfs,hive,hbase \\
    --emr-master-nodes 10.0.0.177,10.0.0.199,10.0.0.21 \\
    --emr-core-nodes 10.0.0.114,10.0.0.136 \\
    --emr-ssh-key /home/ec2-user/key.pem \\
    --restart-interval 30
EOF
    echo ""
    echo "3. Integrate second EMR cluster"
    echo ""
    cat << EOF | sed 's/^ *//'
    sudo ranger-emr-cli-installer/bin/setup.sh install-ranger-plugins \\
    --ranger-host $(hostname -i) \\
    --solr-host $(hostname -i) \\
    --ranger-version 2.1.0 \\
    --ranger-plugins hdfs,hive,hbase \\
    --emr-master-nodes 10.0.0.18 \\
    --emr-core-nodes 10.0.0.69 \\
    --emr-ssh-key /home/ec2-user/key.pem \\
    --restart-interval 30
EOF
    echo ""
}