#!/bin/sh
# install.sh - set up software fan control on a BC-250 board.
#
# What it does:
#   1. Checks for the nct6687 driver; builds it from Fred78290/nct6687d
#      if the kernel does not ship it (installs build deps automatically
#      on Alpine, Debian/Ubuntu, Fedora and Arch-based distros).
#   2. Loads nct6687 with force=true and blacklists the read-only nct6683.
#   3. Makes the module load persistent.
#   4. Installs the fan scripts and the init service (OpenRC or systemd).
#
# Run as root:  doas sh install.sh   (or sudo sh install.sh)
#
# Verified on Alpine Linux. Debian, Fedora and Arch paths are standard
# but may need the kernel headers package matching your running kernel.

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
    # Install build tools + kernel headers with whatever package manager exists
    PKG=""
    for c in apk apt-get dnf pacman; do
        command -v "$c" >/dev/null 2>&1 && { PKG="$c"; break; }
    done
    [ -n "$PKG" ] || { echo "error: no supported package manager (apk/apt/dnf/pacman)"; exit 1; }

    case "$PKG" in
        apk)     PKGS="git make gcc linux-headers lm-sensors" ;;
        apt-get) PKGS="git make gcc linux-headers-amd64 lm-sensors" ;;
        dnf)     PKGS="git make gcc kernel-devel kernel-headers lm_sensors" ;;
        pacman)  PKGS="git make gcc linux-headers lm_sensors" ;;
    esac

    if ! [ -d "/lib/modules/$KERNEL/build" ]; then
        echo "installing build dependencies: $PKGS"
        case "$PKG" in
            apk)     apk add $PKGS ;;
            apt-get) apt-get update && apt-get install -y $PKGS ;;
            dnf)     dnf install -y $PKGS ;;
            pacman)  pacman -Sy --needed --noconfirm $PKGS ;;
        esac
    fi

    [ -d "/lib/modules/$KERNEL/build" ] || {
        echo "error: kernel headers for $KERNEL not found."
        echo "On Fedora install: sudo dnf install kernel-devel-$(uname -r)"
        echo "On Debian/Ubuntu:  sudo apt install linux-headers-$(uname -r)"
        echo "On Arch:           sudo pacman -S linux-headers (match your kernel package)"
        exit 1
    }

    echo "building out-of-tree nct6687d ..."
    command -v git make gcc >/dev/null || \
        { echo "error: git, make and gcc are required"; exit 1; }
    git clone --depth 1 https://github.com/Fred78290/nct6687d /tmp/nct6687d
    make -C /tmp/nct6687d
    # nct6683 claims the same chip; swap the drivers
    rmmod nct6683 2>/dev/null || true
    insmod /tmp/nct6687d/"$KERNEL"/nct6687.ko force=true
    mkdir -p /lib/modules/$KERNEL/kernel/drivers/hwmon
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
install -d -m755 /run/bc250-fan

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
