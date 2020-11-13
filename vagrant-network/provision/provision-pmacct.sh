#!/bin/bash

echo "### provision pmacct..."

apt-get install -y pmacct
cat > /etc/pmacct/pmacctd.conf <<EOF
daemonize: true
interface: eth0
aggregate: src_host, dst_host, src_port, dst_port, proto, tos
plugins: nfprobe[eth0]
nfprobe_receiver: $OPENNMS_IP:$OPENNMS_NETFLOW_PORT
nfprobe_version: 9
nfprobe_direction[eth0]: tag
nfprobe_ifindex[eth0]: tag2
pre_tag_map: /etc/pmacct/pretag.map
timestamps_secs: true
plugin_buffer_size: 1000
EOF

cat > /etc/pmacct/pretag.map <<EOF
# Use a filter to determine direction
# Set 1 for ingress and 2 for egress
#
# Local MAC
set_tag=1 filter='ether dst de:ad:be:ef:00:00' jeq=eval_ifindexes
set_tag=2 filter='ether src de:ad:be:ef:00:00' jeq=eval_ifindexes

# Use a filter to set the ifindexes
set_tag2=2 filter='ether src de:ad:be:ef:00:00' label=eval_ifindexes
set_tag2=2 filter='ether dst de:ad:be:ef:00:00'
EOF

systemctl enable --now pmacctd
