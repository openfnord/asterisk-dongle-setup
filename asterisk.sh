#!/bin/sh

set -e -x

nix-build -A asterisk -o result-asterisk
nix-build -A asterisk-conf -o result-conf

rm -rf /tmp/asterisk || true
mkdir /tmp/asterisk

./result-asterisk/bin/asterisk -C `pwd`/result-conf/etc/asterisk/asterisk.conf -c -f -ddd
# ltrace -s 500 -A 1000 ./result-asterisk/bin/asterisk -C `pwd`/result-conf/etc/asterisk/asterisk.conf -f -ddd 2> ltrace.log
# ./result-asterisk/bin/asterisk -C `pwd`/asterisk.conf -c -f -ddd