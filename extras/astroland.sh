#!/usr/bin/env bash
# Install zacoons' "astroland" Hyprland rice (https://codeberg.org/zacoons/astroland_dots).
#
#   sudo ./extras/astroland.sh                      # clone from Codeberg
#   sudo ./extras/astroland.sh ~/astroland_dots.tar.gz
#   sudo ./extras/astroland.sh ~/src/astroland_dots
#   sudo ./extras/astroland.sh --off                # back to the normal desktop
#
# What the rice needs, and what this script does about it:
#   - Hyprland 0.55.2 with the repo's clamp-to-border patch: installs 0.55.2
#     and its libraries from the Arch archive (pinned via IgnorePkg), then
#     rebuilds the hyprland package from Arch's own PKGBUILD with the patch.
#   - The "astroland" Hyprland plugin: compiled against that Hyprland.
#   - Quickshell, foot, kitty, sox, ffmpeg, tofi, mpd, rmpc, fonts, ...:
#     installed from the repos, or built from the AUR when missing.
#   - Hard-coded /home/zac/... paths: rewritten to where the rice is installed.
#   - Configs: ~/.config/<app> become links into the rice folder. Whatever was
#     there is moved to ~/.config/astroland-backup-<date>/. Your zsh config is
#     left alone (the rice's zshrc aliases sudo to "nope").
#
# Runs as root. The user is $SUDO_USER, or TARGET_USER=name (the installer).
set -euo pipefail

HYPR_VER="0.55.2"
UPSTREAM="https://codeberg.org/zacoons/astroland_dots"
ORIG_DIR="/home/zac/code/astroland_dots"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
log()  { printf '\n\033[1;35m[astroland]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mwarning:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "run with sudo"
TARGET_USER="${TARGET_USER:-${SUDO_USER:-}}"
[[ -n "$TARGET_USER" && "$TARGET_USER" != root ]] || die "run with sudo from your normal user, or set TARGET_USER"
HOME_DIR="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
[[ -d "$HOME_DIR" ]] || die "no home folder for $TARGET_USER"
GROUP="$(id -gn "$TARGET_USER")"

DOTS="$HOME_DIR/.local/share/astroland_dots"
BUILD="/var/tmp/astroland-build"
CFG="$HOME_DIR/.config"
BACKUP="$CFG/astroland-backup-$(date +%Y%m%d-%H%M%S)"
SRC="${1:-$UPSTREAM}"

as_user() { runuser -u "$TARGET_USER" -- env HOME="$HOME_DIR" USER="$TARGET_USER" LOGNAME="$TARGET_USER" "$@"; }

# --- --off: switch back to the normal desktop ----------------------------------
if [[ "${1:-}" == "--off" ]]; then
    log "Removing the astroland config links from $CFG"
    for l in "$CFG"/* "$CFG"/.[!.]*; do
        [[ -L "$l" && "$(readlink "$l")" == "$DOTS"/* ]] && rm "$l"
    done
    last="$(find "$CFG" -maxdepth 1 -type d -name 'astroland-backup-*' | sort | tail -n1)"
    if [[ -n "$last" ]]; then
        log "Restoring your previous configs from $last"
        as_user cp -a "$last/." "$CFG/"
    fi
    # Anything still missing comes from the system defaults.
    as_user cp -an /etc/skel/.config/. "$CFG/" 2>/dev/null || true
    log "Done. Log out and back in. The rice stays in $DOTS; run this script again to switch back."
    exit 0
fi

# makepkg must run as the user but install with pacman: allow exactly that,
# without a password, only while this script runs.
SUDOERS=/etc/sudoers.d/99-astroland-build
echo "$TARGET_USER ALL=(root) NOPASSWD: /usr/bin/pacman" > "$SUDOERS"
chmod 440 "$SUDOERS"
trap 'rm -f "$SUDOERS"' EXIT

# --- 1. Get the rice ----------------------------------------------------------
log "Getting the dotfiles into $DOTS"
as_user mkdir -p "$(dirname "$DOTS")"
if [[ -d "$DOTS" ]]; then
    log "Already there; keeping it (and your saved game). Delete $DOTS to start fresh."
elif [[ -d "$SRC" ]]; then
    cp -a "$SRC" "$DOTS"
elif [[ -f "$SRC" ]]; then
    tmp="$(mktemp -d)"
    tar -xf "$SRC" -C "$tmp"
    top="$(dirname "$(find "$tmp" -maxdepth 3 -name hyprland_clamp_to_border.patch | head -n1)")"
    [[ -d "$top/.config" ]] || die "$SRC doesn't look like astroland_dots"
    cp -a "$top" "$DOTS"
    rm -rf "$tmp"
else
    as_user git clone "$SRC" "$DOTS"
fi
chown -R "$TARGET_USER:$GROUP" "$DOTS"
[[ -f "$DOTS/hyprland_clamp_to_border.patch" && -d "$DOTS/plugin" ]] || die "$DOTS is not astroland_dots"

# --- 2. Packages ----------------------------------------------------------------
log "Installing the programs the rice uses"
PKGS=(
    quickshell qt6-svg qt6-imageformats qt6-5compat
    foot kitty tofi pcmanfm helix fastfetch
    sox ffmpeg mpd rmpc fyi grim playerctl brightnessctl
    hypridle hyprlock
    ttf-martian-mono-nerd
    cmake ninja pkgconf gcc pixman libdrm pango cairo
)
repo=(); aur=()
for p in "${PKGS[@]}"; do
    if pacman -Si "$p" &>/dev/null; then repo+=("$p"); else aur+=("$p"); fi
done
pacman -S --needed --noconfirm "${repo[@]}"

aur_build() {
    local p="$1"
    pacman -Qq "$p" &>/dev/null && return 0
    log "Building $p from the AUR"
    install -d -o "$TARGET_USER" -g "$GROUP" "$BUILD/aur"
    rm -rf "${BUILD:?}/aur/$p"
    as_user git clone --depth 1 "https://aur.archlinux.org/$p.git" "$BUILD/aur/$p"
    [[ -f "$BUILD/aur/$p/PKGBUILD" ]] || { warn "$p is not in the AUR either; skipping"; return 0; }
    (cd "$BUILD/aur/$p" && as_user makepkg -si --noconfirm --needed) || warn "building $p failed; skipping"
}
for p in "${aur[@]}"; do aur_build "$p"; done

# --- 3. Hyprland 0.55.2, pinned ------------------------------------------------
log "Installing Hyprland $HYPR_VER from the Arch archive"
bash "$SCRIPT_DIR/hyprland-pin.sh" "$HYPR_VER"

# --- 4. Rebuild it with the rice's patch ---------------------------------------
MARKER=/usr/share/hyprland/astroland-clamp-to-border.patch
if [[ -f "$MARKER" ]] && [[ "$(pacman -Q hyprland | awk '{print $2}')" == "$HYPR_VER"-* ]]; then
    log "Patched Hyprland $HYPR_VER already installed"
else
    pkgver_rel="$(pacman -Q hyprland | awk '{print $2}')"   # e.g. 0.55.2-1
    log "Building Hyprland $pkgver_rel with the clamp-to-border patch (10-30 minutes)"
    install -d -o "$TARGET_USER" -g "$GROUP" "$BUILD"
    W="$BUILD/hyprland"
    rm -rf "$W"
    as_user mkdir -p "$W"
    tag="${pkgver_rel//:/-}"
    url="https://gitlab.archlinux.org/archlinux/packaging/packages/hyprland/-/archive/$tag/hyprland-$tag.tar.gz"
    as_user curl -fsSL --retry 3 -o "$W/pkgbuild.tar.gz" "$url" || die "cannot download Arch's PKGBUILD ($url)"
    as_user tar -xzf "$W/pkgbuild.tar.gz" -C "$W" --strip-components=1
    [[ -f "$W/PKGBUILD" ]] || die "no PKGBUILD in $url"

    # The patch also touches the tracy submodule pointer; drop that part.
    awk '/^diff --git /{skip = ($0 ~ /subprojects\/tracy/)} !skip' \
        "$DOTS/hyprland_clamp_to_border.patch" > "$W/astroland-clamp-to-border.patch"
    chown "$TARGET_USER:$GROUP" "$W/astroland-clamp-to-border.patch"

    cat >> "$W/PKGBUILD" <<'PKGEOF'

# --- astroland: apply the rice's clamp-to-border patch ---
pkgrel="${pkgrel}.1"
pkgdesc+=" (astroland clamp-to-border patch)"
source+=("astroland-clamp-to-border.patch")
for _a in md5sums sha1sums sha224sums sha256sums sha384sums sha512sums b2sums cksums; do
    if declare -p "$_a" &>/dev/null; then eval "$_a+=('SKIP')"; fi
done
if declare -f prepare >/dev/null; then
    eval "_astro_orig_prepare() $(declare -f prepare | tail -n +2)"
else
    _astro_orig_prepare() { :; }
fi
prepare() {
    _astro_orig_prepare
    local f d
    f="$(find "$srcdir" -maxdepth 4 -path '*/src/render/OpenGL.hpp' -not -path '*/subprojects/*' | head -n1)"
    d="${f%/src/render/OpenGL.hpp}"
    patch -d "$d" -Np1 -i "$srcdir/astroland-clamp-to-border.patch"
}
if declare -f package >/dev/null; then
    eval "_astro_orig_package() $(declare -f package | tail -n +2)"
    package() {
        _astro_orig_package
        install -Dm644 "$srcdir/astroland-clamp-to-border.patch" \
            "$pkgdir/usr/share/hyprland/astroland-clamp-to-border.patch"
    }
fi
PKGEOF
    chown "$TARGET_USER:$GROUP" "$W/PKGBUILD"
    (cd "$W" && as_user makepkg -s --noconfirm --needed) || die "building the patched Hyprland failed (see output above)"
    built="$(find "$W" -maxdepth 1 -name "hyprland-$HYPR_VER-*.pkg.tar.zst" ! -name '*debug*' | head -n1)"
    [[ -n "$built" ]] || die "build finished but no package found in $W"
    pacman -U --noconfirm "$built"
fi

# --- 5. Point the rice at its new home ----------------------------------------
log "Rewriting $ORIG_DIR paths to $DOTS"
{ grep -rlI --exclude-dir=.git "$ORIG_DIR" "$DOTS" || true; } | while read -r f; do
    sed -i "s|$ORIG_DIR|$DOTS|g" "$f"
done

# --- 6. Build the plugin --------------------------------------------------------
log "Building the astroland Hyprland plugin"
rm -rf "$DOTS/plugin/build"
(cd "$DOTS/plugin" && as_user cmake -B build -DCMAKE_BUILD_TYPE=Release && as_user cmake --build build -j"$(nproc)") \
    || die "plugin build failed"

# --- 7. Small additions so it's usable day to day -----------------------------
LUA="$DOTS/.config/hypr/hyprland.lua"
if ! grep -q 'pocket-arch additions' "$LUA"; then
    log "Adding close-window and lock keys to hyprland.lua"
    cat >> "$LUA" <<'LUAEOF'

-- pocket-arch additions (added by extras/astroland.sh)
hl.bind(mainMod .. " + Q", hl.dsp.window.close())
hl.bind(mainMod .. " + ESCAPE", hl.dsp.exec_cmd("qs ipc call lockscreen lock"))
hl.on("hyprland.start", function ()
  hl.exec_cmd("hypridle")
  hl.exec_cmd("nm-applet")
end)
LUAEOF
    if [[ -n "${KB_LAYOUTS:-}" && "$KB_LAYOUTS" != us ]]; then
        cat >> "$LUA" <<LUAEOF
hl.config({ input = { kb_layout = "$KB_LAYOUTS", kb_options = "grp:win_space_toggle" } })
LUAEOF
    fi
fi
# The rice starts its screensaver after 1 second idle; make that 2 minutes.
sed -i 's/^\(\s*timeout\s*=\s*\)1\s*$/\1120/' "$DOTS/.config/hypr/hypridle.conf"

# --- 8. Link the configs -------------------------------------------------------
log "Linking configs into ~/.config"
as_user mkdir -p "$CFG"
for entry in "$DOTS"/.config/* "$DOTS"/.config/.[!.]*; do
    [[ -e "$entry" ]] || continue
    n="$(basename "$entry")"
    [[ "$n" == zsh ]] && continue
    target="$CFG/$n"
    if [[ -L "$target" && "$(readlink "$target")" == "$entry" ]]; then continue; fi
    if [[ -e "$target" || -L "$target" ]]; then
        as_user mkdir -p "$BACKUP"
        mv "$target" "$BACKUP/"
    fi
    as_user ln -s "$entry" "$target"
done
as_user mkdir -p "$HOME_DIR/Music" "$HOME_DIR/.local/state/mpd" "$DOTS/.config/mpd/playlists"
as_user fc-cache -f >/dev/null 2>&1 || true

log "Done."
echo "Log out and back in (or reboot). Keys in this rice use ALT as the main key:"
echo "  ALT+Shift+Enter terminal, ALT+R launcher, ALT+Q close, ALT+Escape lock, ALT+X save game,"
echo "  ALT+1..0 workspaces, ALT+F maximize, ALT+Space float."
[[ -d "$BACKUP" ]] && echo "Your previous configs are in $BACKUP"
echo "To go back to the normal desktop: move those folders back and run 'sudo $SCRIPT_DIR/hyprland-pin.sh --unpin'."
