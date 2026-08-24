#!/bin/sh
# install.sh - set up software fan control on a BC-250 board.
#
# What it does:
#   1. Checks for the nct6687 driver; builds it from Fred78290/nct6687d
#      if the kernel does not ship it (needs git, make, gcc, kernel headers).
#   2. Loads nct6687 with force=true and blacklists the read-only nct6683.
#   3. Makes the module load persistent.
#   4. Installs the fan scripts and the init service (OpenRC or systemd).
#
# Run as root:  doas sh install.sh   (or sudo sh install.sh)
#
# Tested on Alpine Linux (OpenRC). Systemd path is provided but untested.

set -e

[ "$(id -u)" = 0 ] || { echo "run as root: doas sh install.sh"; exit 1; }

REPO_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
KERNEL=$(uname -r)

log() { printf '\n==> %s\n' "$*"; }

# ---------------------------------------------------------------------------
log "1/4 nct6687 driver"

if grep -q nct6687 /proc/modules; then
    echo "nct6687 already loaded"
elif [ -f "/lib/modules/$KERNEL/kernel/drivers/hwmon/nct6687.ko" ] || \
     modprobe nct6687 force=true 2>/dev/null; then
    echo "kernel ships nct6687"
else
    echo "building out-of-tree nct6687d ..."
    command -v git make gcc >/dev/null || \
        { echo "error: git, make and gcc are required (plus kernel headers)"; exit 1; }
    [ -d /lib/modules/$KERNEL/build ] || \
        { echo "error: kernel headers for $KERNEL not found (/lib/modules/$KERNEL/build)"; exit 1; }
    git clone --depth 1 https://github.com/Fred78290/nct6687d /tmp/nct6687d
    make -C /tmp/nct6687d
    # nct6683 claims the same chip; swap the drivers
    rmmod nct6683 2>/dev/null || true
    insmod /tmp/nct6687d/"$KERNEL"/nct6687.ko force=true
    cp /tmp/nct6687d/"$KERNEL"/nct6687.ko /lib/modules/$KERNEL/kernel/drivers/hwmon/
    depmod -a
fi

modprobe nct6687 force=true 2>/dev/null || true
grep -q nct6687 /proc/modules || { echo "error: nct6687 did not load"; exit 1; }

# ---------------------------------------------------------------------------
log "2/4 persistent module loading"

echo blacklist nct6683 > /etc/modprobe.d/nct6683-blacklist.conf
echo "options nct6687 force=true" > /etc/modprobe.d/nct6687.conf
echo nct6687 > /etc/modules-load.d/nct6687.conf

# ---------------------------------------------------------------------------
log "3/4 fan scripts"

install -m755 "$REPO_DIR/scripts/bc250-fan-curve" /usr/local/bin/bc250-fan-curve
install -m755 "$REPO_DIR/scripts/fan" /usr/local/bin/fan

# ---------------------------------------------------------------------------
log "4/4 init service"

if command -v rc-service >/dev/null 2>&1; then
    install -m755 "$REPO_DIR/init/bc250-fan-curve.openrc" /etc/init.d/bc250-fan-curve
    rc-update add bc250-fan-curve default
    rc-service bc250-fan-curve restart || rc-service bc250-fan-curve start
elif command -v systemctl >/dev/null 2>&1; then
    install -m644 "$REPO_DIR/init/bc250-fan-curve.service" /etc/systemd/system/
    systemctl daemon-reload
    systemctl enable --now bc250-fan-curve
else
    echo "no OpenRC or systemd found - start /usr/local/bin/bc250-fan-curve yourself"
    exit 0
fi

echo
echo "done. try:   fan status   |   fan 60   |   fan auto"
