#!/bin/bash                                                                                                                                                                                                                              
CONFIG_REPOSITORY_URL="https://raw.githubusercontent.com/mrebeschini/elastic-zeek-workshop/master"
ZEEK_DIR=/home/ec2-user/zeek

mkdir $ZEEK_DIR
chown ec2-user:ec2-user $ZEEK_DIR

wget $CONFIG_REPOSITORY_URL/beats_install.sh
chmod 755 $ZEEK_DIR/beats_install.sh
