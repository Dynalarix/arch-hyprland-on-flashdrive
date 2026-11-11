# Pocket Arch: Arch Linux + Hyprland on a USB drive

A script that turns a USB flash drive into a full, persistent Arch Linux
install with the Hyprland desktop. Plug it into any x86_64 PC, pick the USB in
the boot menu, and you get your own system with your files, settings and
tools. It is a real install, not a live image: everything you change is kept.

## What you get

- **Boots almost anywhere.** GRUB is installed for legacy BIOS, 64-bit UEFI and
  32-bit UEFI at once, at the fallback paths firmware looks for on removable
  media. It never writes boot entries into the host PC.
- **Drivers for any hardware.** The initramfs is built without `autodetect`, so
  it carries drivers for every disk/USB controller and GPU. Intel and AMD
  microcode, Mesa for Intel/AMD/NVIDIA (nouveau), extra firmware for laptop
  audio and Wi-Fi. A `linux-lts` kernel is a fallback entry in the boot menu.
- **Easy on the flash memory.** `noatime` mounts, the system journal in RAM,
  compressed swap in RAM (zram) instead of a swap file, and writes batched
  every 15 s.
- **Hyprland desktop**, ready to use: Waybar, fuzzel launcher, mako
  notifications, kitty and foot terminals, hyprlock/hypridle, Thunar, Firefox,
  PipeWire audio, Bluetooth, NetworkManager with a tray applet, screenshots and
  clipboard history. Login through a small text greeter (greetd + tuigreet).
- **Shells and tools:** bash with `bash-completion`, zsh (completions,
  autosuggestions, syntax highlighting), fish, starship prompt, zoxide, fzf,
  git, GitHub CLI, neovim/vim/nano, tmux, ripgrep, fd, bat, eza, btop,
  base-devel, and hardware inspection tools (lshw, inxi, smartctl, gparted).

The full list is in [`packages/`](packages). Add or remove lines freely.

## Requirements

- A USB drive of 16 GB or more (a fresh install uses about 8-10 GB). A USB 3
  drive makes a big difference in speed.
- A PC to run the installer on, with internet access.
- An Arch Linux environment to run the script from. Any of these works:
  1. **The official Arch ISO** on a *second* USB stick: boot it, connect to the
     internet (`iwctl` for Wi-Fi), then follow the steps below.
  2. **An existing Arch Linux install.** Install the tools first:
     `sudo pacman -S --needed arch-install-scripts gptfdisk dosfstools parted git`.
  3. **Any other Linux, through a VM** with the target drive passed in. With
     QEMU, download the [Arch ISO](https://archlinux.org/download/) and run
     (replace `/dev/sdX` with the USB drive, see `lsblk`):

     ```sh
     sudo qemu-system-x86_64 -enable-kvm -m 4G -smp 4 \
         -cdrom archlinux-x86_64.iso -boot d \
         -drive file=/dev/sdX,format=raw,if=virtio
     ```

     Inside the VM the drive shows up as `/dev/vda`. On Windows, VirtualBox or
     VMware with USB passthrough works the same way.

## Install

From the Arch environment, as root:

```sh
pacman -Sy --needed git
git clone https://github.com/Dynalarix/arch-hyprland-on-flashdrive
cd arch-hyprland-on-flashdrive

# Optional: edit settings (user name, shell, time zone, keyboard layouts...)
nano config.sh

lsblk                     # find your USB drive, e.g. /dev/sdb
./install.sh /dev/sdX     # ERASES the whole drive
```

The script asks you to type the device name to confirm, then for your user and
root passwords, and runs unattended after that. Expect 15-40 minutes depending
on the drive and the internet connection.

Settings can also be given on the command line, for example:

```sh
USERNAME=alex USER_SHELL=fish TIMEZONE=Europe/Berlin KB_LAYOUTS=us,de ./install.sh /dev/sdb
```

| Setting | Default | Meaning |
|---|---|---|
| `TARGET_HOSTNAME` | `pocket-arch` | Computer name |
| `USERNAME` | `user` | Your login name (in the `wheel` group, can use `sudo`) |
| `USER_SHELL` | `zsh` | `zsh`, `bash` or `fish`. All three are installed; switch later with `chsh` |
| `LOCALES` | `en_US.UTF-8` | Space-separated locales; the first becomes the system language |
| `TIMEZONE` | `UTC` | e.g. `Europe/Moscow`; change later with `timedatectl set-timezone` |
| `CONSOLE_KEYMAP` | `us` | Keyboard layout on the text console |
| `KB_LAYOUTS` | `us` | Hyprland layouts, e.g. `us,ru`. With several, Alt+Shift switches |
| `ROOT_FS` | `ext4` | `ext4`, or `btrfs` for zstd compression and snapshots-ready subvolumes |
| `ESP_SIZE` | `512M` | EFI partition size |
| `INSTALL_LTS_KERNEL` | `yes` | Add `linux-lts` as a fallback boot entry |
| `INSTALL_NVIDIA` | `no` | Proprietary NVIDIA driver. Leave `no` unless you mostly use NVIDIA machines; nouveau works everywhere |

## Using it

1. Plug the drive into a PC and open its boot menu (usually F12, F11, F8, Esc
   or F2 at power-on; on Macs hold Option).
2. Pick the USB entry (on UEFI machines it may be called `UEFI: <drive name>`).
   If it doesn't show, disable **Secure Boot** in the firmware settings.
3. Log in at the greeter. Hyprland starts. Press **SUPER + /** for the keys.

Most useful keys: **SUPER+Enter** terminal, **SUPER+D** app launcher,
**SUPER+Q** close window, **SUPER+1..0** workspaces, **SUPER+Escape** lock.
Wi-Fi is in the tray icon, or run `nmtui`.

Keep the system updated like any Arch install: `sudo pacman -Syu`.

### Unplugging safely

Shut down (`systemctl poweroff`) before pulling the drive. Writes are batched
for up to 15 seconds, so pulling it out of a running system can lose recent
changes.

## Retro CRT theme

`themes/crt/` turns the desktop into an old phosphor-green terminal: a screen
shader with scanlines, RGB phosphor stripes, colour fringing and darker edges,
square green window borders with a soft glow, plus matching Waybar, kitty,
foot, fuzzel, mako and lock screen. Apply it from inside the installed system,
as your normal user:

```sh
git clone https://github.com/Dynalarix/arch-hyprland-on-flashdrive
cd arch-hyprland-on-flashdrive
./themes/crt/apply.sh          # ./themes/crt/apply.sh --off to undo
```

- **SUPER+SHIFT+S** switches the CRT screen effect on and off (handy for games
  or video, since the shader costs some GPU).
- Tune it in `~/.config/hypr/shaders/crt.frag`: scanline strength, glow,
  `TINT = 1.0` for a fully green monochrome screen (or amber), and `CURVE` for a
  bulging tube. Run `hyprctl reload` to see changes.

## Disk layout

| # | Size | Type | Use |
|---|---|---|---|
| 1 | 1 MiB | BIOS boot | GRUB for legacy BIOS |
| 2 | 512 MiB | FAT32 (ESP) | GRUB for UEFI, `\EFI\BOOT\BOOTX64.EFI` and `BOOTIA32.EFI` |
| 3 | rest | ext4 or btrfs | The system and your home folder |

All mounts use UUIDs, so device names changing between PCs doesn't matter.

## Troubleshooting

- **Black screen after the greeter, or Hyprland won't start:** Hyprland needs
  a working GPU driver. In a VM, enable 3D acceleration (QEMU: `-vga virtio
  -display gtk,gl=on`). On NVIDIA machines with nouveau, older cards may
  struggle; press Ctrl+Alt+F2 for a text console and check
  `journalctl -b` for errors.
- **No Wi-Fi on a specific laptop:** some Broadcom chips need
  `broadcom-wl-dkms`; plug in Ethernet or use phone USB tethering, then
  `sudo pacman -S broadcom-wl-dkms`.
- **Wrong clock on a Windows PC:** time comes from the network
  (systemd-timesyncd); it corrects itself once online.
- **Logs from a previous boot:** the journal lives in RAM to save writes. Set
  `Storage=persistent` in `/etc/systemd/journald.conf.d/10-volatile.conf` to
  keep them.

## Files

```
install.sh          partitions the drive, installs packages, copies configs
chroot-setup.sh     runs inside the new system: locale, initramfs, GRUB, users, services
config.sh           settings
packages/*.txt      package lists (base system, desktop, tools)
files/etc/          system config copied to /etc (initramfs, journald, zram, greeter...)
files/skel/         dotfiles for new users (Hyprland, Waybar, zsh, bash, fish)
```
