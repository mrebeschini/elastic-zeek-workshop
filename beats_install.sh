#!/bin/bash
CONFIG_REPOSITORY_URL="https://raw.githubusercontent.com/mrebeschini/elastic-zeek-workshop/master"
AUDITD_ATTACK_RULES_URL="https://raw.githubusercontent.com/bfuzzy/auditd-attack/master/auditd-attack.rules"
ZEEK_LOGS_DIR=/home/ec2-user/zeek/logs
ZEEK_DIR=$HOME/zeek

echo "************************************************"
echo "* Elastic/Zeek BSides Workshop Beats Installer *"
echo "************************************************"

if [[ $EUID -ne 0 ]]; then
   echo "Error: this script must be run as root."
   exit 1
fi

echo "Enter your Elastic Cloud CLOUD_ID then press [ENTER]"
read CLOUD_ID
if [ -z "$CLOUD_ID" ]; then
    echo "Error: CLOUD_ID must be set to a non-empty value!"
    exit 1
fi
echo -e "Your CLOUD_ID is set to $CLOUD_ID\n"
echo "Enter you Elastic Cloud 'elastic' user password and then press [ENTER]"
read CLOUD_AUTH
if [ -z "$CLOUD_AUTH" ]; then
    echo "Error: CLOUD_AUTH must be set to a non-empty value!"
    exit 1
fi
echo -e "Your 'elastic' user password is set to $CLOUD_AUTH\n"
echo "Ready to Install? [y|n]"
read CONTINUE
case "$CONTINUE" in
 [Yy]) echo -e "\nElastic Beats Installation Initiated";;
    *) echo -e "\nInstallation aborted";exit;;
esac

echo -e "\nDownloading Elastic yum repo configuration..."
rpm --import https://packages.elastic.co/GPG-KEY-elasticsearch
wget -q -N $CONFIG_REPOSITORY_URL/elastic-7.x.repo -P /etc/yum.repos.d/

function install_beat() {
    BEAT_NAME=$1
    echo -e "\n*** Installing $BEAT_NAME ****";

    if [ $BEAT_NAME == "heartbeat" ]; then
        BEAT_PKG_NAME="heartbeat-elastic"
    else
        BEAT_PKG_NAME=$BEAT_NAME
    fi

    yum -q list installed $BEAT_PKG_NAME &> /dev/null
    if [ $? -eq 0 ]; then
        echo "$BEAT_NAME was previously installed. Uninstalling first..."
        yum -y -q remove $BEAT_PKG_NAME &> /dev/null
        rm -Rf /etc/$BEAT_NAME /var/lib/$BEAT_NAME /var/log/$BEAT_NAME /usr/share/$BEAT_NAME
    fi

    yum -y install $BEAT_PKG_NAME
    echo "Downloading $BEAT_NAME config file..."
    wget -q -N $CONFIG_REPOSITORY_URL/$BEAT_NAME.yml -P /etc/$BEAT_NAME
    chmod go-w /etc/$BEAT_NAME/$BEAT_NAME.yml
    echo "Setting up $BEAT_NAME keystore with Elastic Cloud credentials"
    $BEAT_NAME keystore create
    echo $CLOUD_ID | $BEAT_NAME keystore add CLOUD_ID --stdin
    echo $CLOUD_AUTH | $BEAT_NAME keystore add --stdin CLOUD_AUTH --force
    if [ $? -ne 0 ]; then
        echo "Invalid CLOUD_ID. Installation aborted!"
        exit 2
    fi

    case $BEAT_NAME in
        auditbeat)
            wget -q $AUDITD_ATTACK_RULES_URL -N -O /etc/auditbeat/audit.rules.d/auditd-attack.rules.conf
            echo "Stopping auditd deamon"
            service auditd stop &> /dev/null
            chkconfig auditd off &> /dev/null
            ;;
        filebeat)
            #Download pre-generated Zeek Logs for CTF exercises
            wget -q -N $CONFIG_REPOSITORY_URL/zeek-logs.tar.gz -N -O /tmp/zeek-logs.tar.gz
	    if [ -d $ZEEK_LOGS_DIR ]; then
	      rm -Rf $ZEEK_LOGS_DIR
	    fi
	    mkdir -p $ZEEK_LOGS_DIR
	    tar xfvz /tmp/zeek-ctf-logs.tar.gz -C $ZEEK_LOGS_DIR > /dev/null
	    rm -f /tmp/zeek-ctf-logs.tar.gz
	    chown -R ec2-user:ec2-user $ZEEK_LOGS_DIR
	    wget -q $CONFIG_REPOSITORY_URL/zeek.yml -O /etc/filebeat/modules.d/zeek.yml

            $BEAT_NAME modules enable system
            ;;
    esac

    echo "Setting up $BEAT_NAME"
    $BEAT_NAME setup
    systemctl enable $BEAT_PKG_NAME
    systemctl start $BEAT_PKG_NAME
    $BEAT_NAME test output
    echo -e "$BEAT_NAME setup complete"
}

function decode_cloud_id() {                                                                                                                                         BASE64URL=`echo "$CLOUD_ID" | awk -F':' '{ print $2 }'`                                                                                                            URL=`echo $BASE64URL | base64 --decode`

  ES=`echo $URL | awk -F'$' '{ print $2 }'`
  REGION=`echo $URL | awk -F'$' '{ print $1 }'`

  ES_URL=https://$ES.$REGION
}

#Load up ingest pipelines
decode_cloud_id
echo -e "\nLoading MITRE/GEO Ingest Pipelines into ${ES_URL}"
wget -q -N $CONFIG_REPOSITORY_URL/pipeline_generic_geo.json
wget -q -N $CONFIG_REPOSITORY_URL/pipeline_mitre_geo_auditbeat.json
wget -q -N $CONFIG_REPOSITORY_URL/pipeline_mitre_geo_winlogbeat.json
curl --silent --user elastic:$CLOUD_AUTH -XPUT "${ES_URL}/_ingest/pipeline/geoip-info" -H "Content-Type: application/json" -d @pipeline_generic_geo.json
curl --silent --user elastic:$CLOUD_AUTH -XPUT "${ES_URL}/_ingest/pipeline/mitre_auditbeat" -H "Content-Type: application/json" -d @pipeline_mitre_geo_auditbeat.json
curl --silent --user elastic:$CLOUD_AUTH -XPUT "${ES_URL}/_ingest/pipeline/windows_geo_mitre" -H "Content-Type: application/json" -d @pipeline_mitre_geo_winlogbeat.json
rm -f pipeline_*.json

#Install Beats
install_beat "auditbeat"
install_beat "metricbeat"
install_beat "filebeat"
install_beat "heartbeat"

echo -e "\n\nSetup complete!"
