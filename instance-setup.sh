#!/bin/bash                                                                                                                                                                                                                              
CONFIG_REPOSITORY_URL="https://raw.githubusercontent.com/mrebeschini/elastic-zeek-workshop/master"
ZEEK_DIR=/home/ubuntu/zeek

mkdir $ZEEK_DIR
chown ubuntu:ubuntu $ZEEK_DIR

wget $CONFIG_REPOSITORY_URL/beats_install.sh
