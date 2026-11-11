#!/usr/bin/env bash
# Install a portable Arch Linux + Hyprland system onto a USB drive.
#
# Run this as root from an Arch Linux environment (the official Arch ISO, or an
# existing Arch install):
#
#     ./install.sh /dev/sdX
#
# EVERYTHING ON THE TARGET DRIVE IS ERASED.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=config.sh
source "$SCRIPT_DIR/config.sh"

MNT="${MNT:-/mnt/pocket-arch}"

log()  { printf '\n\033[1;32m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33mwarning:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

usage() {
    cat <<EOF
Usage: $0 /dev/sdX

Erases the given drive and installs a bootable, portable Arch Linux with
Hyprland on it. Settings are read from config.sh.

Available disks:
EOF
    lsblk -d -o NAME,SIZE,MODEL,TRAN,RM -e 7,11 || true
    exit 1
}

# --- Checks -------------------------------------------------------------------
[[ $# -eq 1 ]] || usage
DEV="$1"

[[ $EUID -eq 0 ]] || die "run as root (sudo $0 $DEV)"
[[ -b "$DEV" ]] || die "$DEV is not a block device"
[[ "$(lsblk -dno TYPE "$DEV")" == "disk" ]] || die "$DEV is a partition; pass the whole disk, e.g. /dev/sdb"
[[ "$(uname -m)" == "x86_64" ]] || die "only x86_64 hosts are supported"
for cmd in pacstrap arch-chroot genfstab sgdisk mkfs.fat wipefs partprobe; do
    command -v "$cmd" >/dev/null || die "missing '$cmd'. Run this from the Arch ISO or install arch-install-scripts, gptfdisk, dosfstools, parted"
done
case "$ROOT_FS" in
    ext4)  command -v mkfs.ext4  >/dev/null || die "missing mkfs.ext4 (e2fsprogs)" ;;
    btrfs) command -v mkfs.btrfs >/dev/null || die "missing mkfs.btrfs (btrfs-progs)" ;;
    *) die "ROOT_FS must be ext4 or btrfs, not '$ROOT_FS'" ;;
esac
case "$USER_SHELL" in
    zsh|bash|fish) ;;
    *) die "USER_SHELL must be zsh, bash or fish, not '$USER_SHELL'" ;;
esac
[[ "$USERNAME" =~ ^[a-z_][a-z0-9_-]*$ ]] || die "USERNAME '$USERNAME' is not a valid Linux user name"

# Refuse to touch the disk we are running from.
root_src="$(findmnt -no SOURCE / || true)"
if [[ -n "$root_src" && -b "$root_src" ]]; then
    root_disk="/dev/$(lsblk -no PKNAME "$root_src" 2>/dev/null | head -n1)"
    [[ "$root_disk" != "$DEV" ]] || die "$DEV holds the running system"
fi

# --- Confirmation and passwords -----------------------------------------------
echo
lsblk -o NAME,SIZE,FSTYPE,LABEL,MODEL,TRAN "$DEV"
echo
size_bytes="$(lsblk -bdno SIZE "$DEV")"
(( size_bytes >= 16 * 1024 * 1024 * 1024 )) || warn "$DEV is smaller than 16 GB; the install needs about 10 GB"
[[ "$(lsblk -dno TRAN "$DEV")" == "usb" ]] || warn "$DEV does not look like a USB drive. Double-check the name!"

echo "ALL DATA ON $DEV WILL BE DESTROYED."
read -r -p "Type the device name ($DEV) to continue: " answer
[[ "$answer" == "$DEV" ]] || die "aborted"

ask_password() {
    local prompt="$1" p1 p2
    while true; do
        read -r -s -p "$prompt: " p1; echo >&2
        read -r -s -p "Repeat: " p2; echo >&2
        [[ -n "$p1" && "$p1" == "$p2" ]] && { printf '%s' "$p1"; return; }
        echo "Passwords are empty or don't match, try again." >&2
    done
}
USER_PASSWORD="$(ask_password "Password for user '$USERNAME'")"
ROOT_PASSWORD="$(ask_password "Password for root")"

# --- Package list -------------------------------------------------------------
read_list() { sed -e 's/#.*//' -e 's/[[:space:]]*$//' -e '/^$/d' "$@"; }
mapfile -t PACKAGES < <(read_list "$SCRIPT_DIR"/packages/*.txt)
[[ "$INSTALL_LTS_KERNEL" == "yes" ]] && PACKAGES+=(linux-lts linux-lts-headers)
[[ "$INSTALL_NVIDIA" == "yes" ]] && PACKAGES+=(nvidia-open-dkms nvidia-utils)

log "Refreshing package databases"
pacman -Sy --noconfirm

# Drop names the repos no longer know (Arch renames packages now and then) so
# one stale entry doesn't abort the whole install.
missing=()
mapfile -t known < <(pacman -Slq)
declare -A have=()
for p in "${known[@]}"; do have[$p]=1; done
VALID=()
for p in "${PACKAGES[@]}"; do
    if [[ -n "${have[$p]:-}" ]] || pacman -Sp --print-format '%n' "$p" &>/dev/null; then
        VALID+=("$p")
    else
        missing+=("$p")
    fi
done
((${#missing[@]} == 0)) || warn "skipping packages not found in the repos: ${missing[*]}"

# --- Partitioning -------------------------------------------------------------
# GPT with three partitions:
#   1  1 MiB   BIOS boot   (GRUB core image for legacy BIOS machines)
#   2  ESP     FAT32       (GRUB for UEFI machines, at the fallback path)
#   3  rest    root        (ext4 or btrfs)
log "Partitioning $DEV"
umount -R "$MNT" 2>/dev/null || true
# Unmount every partition of the drive, wherever it is mounted (/mnt, or
# /run/media/... from a desktop automounter). Wiping a mounted drive leaves a
# dead mount behind that fails later with "Input/output error".
for part in $(lsblk -lnpo NAME "$DEV" | tail -n +2); do
    swapoff "$part" 2>/dev/null || true
    while read -r target; do
        [[ -n "$target" ]] || continue
        umount "$target" 2>/dev/null || umount -l "$target" \
            || die "cannot unmount $part from $target; close programs using it and retry"
    done < <(findmnt -rno TARGET --source "$part" 2>/dev/null)
done
if lsblk -lno MOUNTPOINTS "$DEV" | grep -q .; then
    die "$DEV is still mounted:
$(lsblk -o NAME,MOUNTPOINTS "$DEV")"
fi
# A parent directory left broken by an earlier failed run.
if ! stat "$(dirname "$MNT")" >/dev/null 2>&1; then
    die "$(dirname "$MNT") is unreadable (stale mount from an earlier run?). Run: umount -l $(dirname "$MNT")"
fi
wipefs -af "$DEV"
sgdisk --zap-all "$DEV"
sgdisk -n 1:0:+1M        -t 1:ef02 -c 1:BIOSBOOT \
       -n 2:0:+"$ESP_SIZE" -t 2:ef00 -c 2:ESP \
       -n 3:0:0          -t 3:8304 -c 3:ROOT \
       "$DEV"
# Mark the BIOS boot partition "legacy BIOS bootable" for picky old firmware.
sgdisk -A 1:set:2 "$DEV" >/dev/null 2>&1 || true
partprobe "$DEV"
udevadm settle

# /dev/sdb -> /dev/sdb1, /dev/nvme0n1 -> /dev/nvme0n1p1, /dev/mmcblk0 -> /dev/mmcblk0p1
if [[ "$DEV" =~ [0-9]$ ]]; then P="${DEV}p"; else P="$DEV"; fi
ESP="${P}2"
ROOT="${P}3"
for _ in $(seq 1 20); do [[ -b "$ROOT" ]] && break; sleep 0.5; done
[[ -b "$ESP" && -b "$ROOT" ]] || die "partitions did not appear ($ESP, $ROOT)"

log "Creating filesystems"
mkfs.fat -F 32 -n POCKETESP "$ESP"
if [[ "$ROOT_FS" == "ext4" ]]; then
    mkfs.ext4 -F -L pocketroot "$ROOT"
    mkdir -p "$MNT"
    mount -o noatime,commit=60 "$ROOT" "$MNT"
else
    mkfs.btrfs -f -L pocketroot "$ROOT"
    mkdir -p "$MNT"
    mount "$ROOT" "$MNT"
    for sv in @ @home @log @pkg @snapshots; do btrfs subvolume create "$MNT/$sv"; done
    umount "$MNT"
    opts="noatime,compress=zstd:3,commit=60"
    mount -o "$opts,subvol=@" "$ROOT" "$MNT"
    mkdir -p "$MNT"/{home,var/log,var/cache/pacman/pkg,.snapshots}
    mount -o "$opts,subvol=@home"      "$ROOT" "$MNT/home"
    mount -o "$opts,subvol=@log"       "$ROOT" "$MNT/var/log"
    mount -o "$opts,subvol=@pkg"       "$ROOT" "$MNT/var/cache/pacman/pkg"
    mount -o "$opts,subvol=@snapshots" "$ROOT" "$MNT/.snapshots"
fi
mkdir -p "$MNT/boot/efi"
mount -o noatime,umask=0077 "$ESP" "$MNT/boot/efi"

# --- Base system --------------------------------------------------------------
log "Installing ${#VALID[@]} packages (this takes a while on a USB stick)"
pacstrap -K "$MNT" "${VALID[@]}"

log "Writing fstab"
genfstab -U "$MNT" > "$MNT/etc/fstab"
# genfstab copies 'relatime' from the live mounts; prefer noatime to save writes.
sed -i 's/relatime/noatime/' "$MNT/etc/fstab"

log "Copying configuration files"
cp -a "$SCRIPT_DIR/files/etc/." "$MNT/etc/"
cp -a "$SCRIPT_DIR/files/skel/." "$MNT/etc/skel/"
install -Dm755 "$SCRIPT_DIR/files/hyprland-session" "$MNT/usr/local/bin/hyprland-session"

# Hand the settings and passwords to the chroot step through a root-only file.
install -d -m 700 "$MNT/root/pocket-installer"
cp "$SCRIPT_DIR/chroot-setup.sh" "$MNT/root/pocket-installer/"
{
    printf 'TARGET_HOSTNAME=%q\n' "$TARGET_HOSTNAME"
    printf 'USERNAME=%q\n' "$USERNAME"
    printf 'USER_SHELL=%q\n' "$USER_SHELL"
    printf 'LOCALES=%q\n' "$LOCALES"
    printf 'TIMEZONE=%q\n' "$TIMEZONE"
    printf 'CONSOLE_KEYMAP=%q\n' "$CONSOLE_KEYMAP"
    printf 'KB_LAYOUTS=%q\n' "$KB_LAYOUTS"
    printf 'INSTALL_NVIDIA=%q\n' "$INSTALL_NVIDIA"
    printf 'TARGET_DEV=%q\n' "$DEV"
    printf 'USER_PASSWORD=%q\n' "$USER_PASSWORD"
    printf 'ROOT_PASSWORD=%q\n' "$ROOT_PASSWORD"
} > "$MNT/root/pocket-installer/settings"
chmod 600 "$MNT/root/pocket-installer/settings"
unset USER_PASSWORD ROOT_PASSWORD

log "Configuring the system inside chroot"
arch-chroot "$MNT" bash /root/pocket-installer/chroot-setup.sh
rm -rf "$MNT/root/pocket-installer"
# arch-chroot bind-mounts the host's resolv.conf, so point it at
# systemd-resolved only now that the chroot is gone.
ln -sf ../run/systemd/resolve/stub-resolv.conf "$MNT/etc/resolv.conf"

log "Flushing writes to the drive (can take a minute)"
# pacman-key can leave gpg-agent/keyboxd running from the new system's
# keyring, which keeps the mount busy.
gpgconf --homedir "$MNT/etc/pacman.d/gnupg" --kill all 2>/dev/null || true
sync
for _ in 1 2 3 4 5; do
    umount -R "$MNT" 2>/dev/null && break
    sleep 2
done
if mountpoint -q "$MNT"; then
    warn "$MNT is still busy. Processes using it:"
    fuser -vm "$MNT" 2>&1 || true
    die "the install itself finished. Close those processes, run 'umount -R $MNT', then unplug."
fi

log "Done. Unplug $DEV and boot any PC from it (pick the USB in the boot menu)."
echo "Log in as '$USERNAME' and Hyprland starts. Press SUPER+/ for the key cheat sheet."
