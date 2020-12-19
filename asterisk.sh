#!/bin/sh

CWD=`pwd`
ME=`basename $0`
TELEGRAM_SESSION="$CWD/telegram.session"

set -e -x

# 1. Build required applications

nix-build -A python_secrets_json -o result-python-secrets
PYTHON_SECRETS=`readlink ./result-python-secrets`

nix-build -A sox -o result-sox
export PATH=`readlink ./result-sox`/bin/:$PATH
sox --version

nix-build -A asterisk -o result-asterisk -K
nix-build -A asterisk-conf -o result-conf \
          --argstr telegram_session "$TELEGRAM_SESSION"
nix-build -A python-scripts -o result-python
nix-build -A tg2sip -o result-tg2sip
nix-build -A tg2sip-conf -o result-tg2sip-conf

# 2. Prepare the modem. We may need to switch it to the serial mode.

try_to_deal_with() {
  vendor="$1"
  product="$2"
  if lsusb | grep -q "$vendor:$product" ; then
    sudo $CWD/result-modeswitch/usr/sbin/usb_modeswitch -v "$vendor" -p "$product" -X
    sleep 0.5
    return 0
  else
    return 1
  fi
}

wait_for_chardev() {
  device=$1
  ncheck=10
  while ! test -c "$device" ; do
    echo -n .
    sleep 1
    ncheck=`expr $ncheck - 1`
    if test "$ncheck" = "0" ; then
      return 1
    fi
  done
  return 0
}

DEVICE="/dev/ttyUSB0"
try_to_deal_with "12d1" "1446" && wait_for_chardev "$DEVICE"

if ! test -c "$DEVICE" ; then
  echo "Can't make $DEVICE to appear. Did you plugged-in the supported GSM "\
       "modem? Consider reviewing and updating this script (\`$0\`)."
  exit 1
fi

# 3. Preparing Telegram session

$CWD/result-python/bin/telegram_check.py --session="$TELEGRAM_SESSION" \
                                          --secret="$PYTHON_SECRETS"


# 4. Run TG2SIP

trap "trap - SIGTERM && kill -- -$$" SIGINT SIGTERM EXIT
mkdir /tmp/tg2sip || true
cp -f $CWD/result-tg2sip-conf/etc/settings.ini /tmp/tg2sip/settings.ini
( cd /tmp/tg2sip && $CWD/result-tg2sip/bin/gen_db; )
( cd /tmp/tg2sip && $CWD/result-tg2sip/bin/tg2sip; ) &

# 5. Run Asterisk daemon synchronously, verbosely, interactively

sudo rm -rf /tmp/asterisk || true
sudo mkdir /tmp/asterisk

sudo ./result-asterisk/bin/asterisk -C $CWD/result-conf/etc/asterisk/asterisk.conf -c -f -vvvvvvvvv

