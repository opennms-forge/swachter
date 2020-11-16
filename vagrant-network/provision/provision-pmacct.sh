#!/bin/bash

echo "### provision pmacct..."

apt-get install -y pmacct

echo "### configure pmacct..."

set +e
amm configure-pmacct.sc || exit $?
set -e

systemctl enable --now pmacctd
