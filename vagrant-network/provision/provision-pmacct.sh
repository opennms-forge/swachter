#!/bin/bash

echo "### provision pmacct..."

apt-get install -y pmacct

echo "### configure pmacct..."

java -version
echo "path: $PATH"

#amm configure-pmacct.sc
java -Xmx500m -XX:+UseG1GC -cp /usr/local/bin/amm ammonite.Main configure-pmacct.sc

systemctl enable --now pmacctd
