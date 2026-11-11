# shellcheck shell=bash
# Settings for install.sh. Edit these before running, or override any of them
# from the environment, e.g.:  USERNAME=alice USER_SHELL=fish ./install.sh /dev/sdX

# --- Identity -----------------------------------------------------------------
TARGET_HOSTNAME="${TARGET_HOSTNAME:-pocket-arch}"
USERNAME="${USERNAME:-user}"
# Login shell for your user: zsh, bash or fish (all three get installed).
USER_SHELL="${USER_SHELL:-zsh}"

# --- Locale -------------------------------------------------------------------
# Space-separated list of locales to generate. The first one becomes LANG.
LOCALES="${LOCALES:-en_US.UTF-8}"
# Any zone from /usr/share/zoneinfo, e.g. Europe/Moscow. Changeable later with
# `timedatectl set-timezone`.
TIMEZONE="${TIMEZONE:-UTC}"
# Console keymap (TTY), see `localectl list-keymaps`.
CONSOLE_KEYMAP="${CONSOLE_KEYMAP:-us}"
# Keyboard layouts inside Hyprland, comma-separated, e.g. "us,ru" or "us,de".
# With more than one, Alt+Shift switches between them.
KB_LAYOUTS="${KB_LAYOUTS:-us}"

# --- Disk layout --------------------------------------------------------------
# EFI system partition size. Kernels live on the root partition, so this only
# holds GRUB's EFI binaries and can stay small.
ESP_SIZE="${ESP_SIZE:-512M}"
# Root filesystem: ext4 (simple, robust) or btrfs (zstd compression, fewer writes).
ROOT_FS="${ROOT_FS:-ext4}"

# --- Optional extras ----------------------------------------------------------
# Install linux-lts as a second, fallback kernel in the boot menu (yes/no).
INSTALL_LTS_KERNEL="${INSTALL_LTS_KERNEL:-yes}"
# Proprietary NVIDIA driver (yes/no). Leave "no" for maximum portability: the
# open-source nouveau driver works everywhere without extra setup.
INSTALL_NVIDIA="${INSTALL_NVIDIA:-no}"
