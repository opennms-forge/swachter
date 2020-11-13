#!/bin/bash

echo "### provision snmp..."
apt-get install -y snmp snmpd
cp snmpd.conf /etc/snmp
systemctl restart snmpd
