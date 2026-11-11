#!/usr/bin/env bash
# Runs inside arch-chroot. Called by install.sh; not meant to be run by hand.
set -euo pipefail

# shellcheck source=/dev/null
source /root/pocket-installer/settings

log() { printf '\n\033[1;32m  -> %s\033[0m\n' "$*"; }

# --- Time, locale, keyboard, hostname -----------------------------------------
log "Locale and time"
ln -sf "/usr/share/zoneinfo/$TIMEZONE" /etc/localtime
# The drive moves between PCs, some of which run Windows (local-time RTC). Keep
# the RTC untouched and get the time from the network instead.
systemctl enable systemd-timesyncd.service

for loc in $LOCALES; do
    sed -i "s/^#\s*\(${loc//./\\.}\s\)/\1/" /etc/locale.gen
done
locale-gen
echo "LANG=${LOCALES%% *}" > /etc/locale.conf
echo "KEYMAP=$CONSOLE_KEYMAP" > /etc/vconsole.conf

echo "$TARGET_HOSTNAME" > /etc/hostname
cat > /etc/hosts <<EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   $TARGET_HOSTNAME.localdomain $TARGET_HOSTNAME
EOF

# --- Initramfs that boots on any hardware -------------------------------------
# files/etc/mkinitcpio.conf.d/portable.conf drops the 'autodetect' hook, so the
# initramfs carries drivers for all storage/USB controllers and GPUs, not just
# the ones of the machine that built it.
log "Building initramfs"
mkinitcpio -P

# --- Boot loader: GRUB for legacy BIOS *and* UEFI ----------------------------
log "Installing GRUB (BIOS + UEFI)"
grub-install --target=i386-pc --recheck "$TARGET_DEV"
# --removable puts GRUB at \EFI\BOOT\BOOTX64.EFI, the path every UEFI firmware
# tries on removable media, and --no-nvram leaves the host PC's boot entries
# alone.
grub-install --target=x86_64-efi --efi-directory=/boot/efi --boot-directory=/boot \
    --removable --no-nvram --recheck
# 32-bit UEFI (some cheap tablets and old Macs). Harmless elsewhere.
grub-install --target=i386-efi --efi-directory=/boot/efi --boot-directory=/boot \
    --removable --no-nvram --recheck || true

sed -i \
    -e 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=3/' \
    -e 's/^#\?GRUB_DISABLE_SUBMENU=.*/GRUB_DISABLE_SUBMENU=y/' \
    /etc/default/grub
grep -q '^GRUB_DISABLE_SUBMENU=' /etc/default/grub || echo 'GRUB_DISABLE_SUBMENU=y' >> /etc/default/grub
if [[ "$INSTALL_NVIDIA" == "yes" ]]; then
    sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT="\(.*\)"/GRUB_CMDLINE_LINUX_DEFAULT="\1 nvidia_drm.modeset=1"/' /etc/default/grub
fi
grub-mkconfig -o /boot/grub/grub.cfg

# --- Users --------------------------------------------------------------------
log "Creating user $USERNAME"
echo "root:$ROOT_PASSWORD" | chpasswd
useradd -m -G wheel,video,audio,input,storage,network -s "/usr/bin/$USER_SHELL" "$USERNAME"
echo "$USERNAME:$USER_PASSWORD" | chpasswd
echo '%wheel ALL=(ALL:ALL) ALL' > /etc/sudoers.d/10-wheel
chmod 440 /etc/sudoers.d/10-wheel

# Keyboard layouts for Hyprland.
sed -i "s/^\(\s*kb_layout\s*=\).*/\1 $KB_LAYOUTS/" "/home/$USERNAME/.config/hypr/hyprland.conf"
if [[ "$KB_LAYOUTS" == *,* ]]; then
    sed -i "s/^\(\s*kb_options\s*=\).*/\1 grp:alt_shift_toggle/" "/home/$USERNAME/.config/hypr/hyprland.conf"
fi

# --- Services -----------------------------------------------------------------
log "Enabling services"
systemctl enable NetworkManager.service
systemctl enable bluetooth.service
systemctl enable greetd.service
systemctl enable fstrim.timer
systemctl enable systemd-resolved.service

# Per-user services (polkit agent, audio) are started by Hyprland/systemd --user.
sudo -u "$USERNAME" xdg-user-dirs-update || true

log "Chroot setup finished"
