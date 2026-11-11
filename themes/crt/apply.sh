#!/usr/bin/env bash
# Apply the retro CRT theme to the current user's desktop.
#
#   ./apply.sh         install / update the theme
#   ./apply.sh --off   go back to the default look
#
# Run as your normal user (not root) inside the installed system. Your old
# config files are backed up to ~/.config/crt-theme-backup-<date>/ first.
set -euo pipefail

THEME_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CFG="${XDG_CONFIG_HOME:-$HOME/.config}"
HYPR_CONF="$CFG/hypr/hyprland.conf"
SOURCE_LINE="source = $CFG/hypr/theme-crt.conf"
MARK="# crt-theme"

[[ $EUID -ne 0 ]] || { echo "Run this as your normal user, not root." >&2; exit 1; }
[[ -f "$HYPR_CONF" ]] || { echo "No $HYPR_CONF found." >&2; exit 1; }

reload() {
    if [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; then
        hyprctl reload >/dev/null
        pkill -x waybar 2>/dev/null || true
        (waybar >/dev/null 2>&1 &)
        makoctl reload 2>/dev/null || { pkill -x mako 2>/dev/null; (mako >/dev/null 2>&1 &); }
        pkill -USR1 -x kitty 2>/dev/null || true
    fi
}

latest_backup() { find "$CFG" -maxdepth 1 -name "crt-theme-backup-*" -type d 2>/dev/null | sort | tail -n1; }

if [[ "${1:-}" == "--off" ]]; then
    sed -i "/$MARK\$/d" "$HYPR_CONF"
    sed -i "/^include theme-crt.conf/d" "$CFG/kitty/kitty.conf" 2>/dev/null || true
    backup="$(latest_backup)"
    if [[ -n "$backup" ]]; then
        echo "Restoring files from $backup"
        cp -a "$backup/." "$CFG/"
    fi
    reload
    echo "CRT theme switched off."
    exit 0
fi

# The retro-looking IBM Plex Mono (Nerd Font build) used by the theme.
if ! fc-list | grep -q "BlexMono Nerd Font"; then
    echo "Installing the BlexMono Nerd Font (needs sudo)..."
    sudo pacman -S --needed --noconfirm ttf-ibmplex-mono-nerd
fi

# Back up everything we are about to overwrite (only on the first apply).
if [[ -z "$(latest_backup)" ]]; then
    backup="$CFG/crt-theme-backup-$(date +%Y%m%d-%H%M%S)"
    for f in hypr/hyprlock.conf waybar/style.css foot/foot.ini fuzzel/fuzzel.ini mako/config; do
        if [[ -f "$CFG/$f" ]]; then
            mkdir -p "$backup/$(dirname "$f")"
            cp -a "$CFG/$f" "$backup/$f"
        fi
    done
    mkdir -p "$backup"
    echo "Backed up your current files to $backup"
fi

install -Dm644 "$THEME_DIR/hypr/shaders/crt.frag"    "$CFG/hypr/shaders/crt.frag"
install -Dm755 "$THEME_DIR/hypr/scripts/crt-toggle.sh" "$CFG/hypr/scripts/crt-toggle.sh"
install -Dm644 "$THEME_DIR/hypr/hyprlock.conf"       "$CFG/hypr/hyprlock.conf"
sed "s|@SHADER@|$CFG/hypr/shaders/crt.frag|" "$THEME_DIR/hypr/theme-crt.conf" > "$CFG/hypr/theme-crt.conf"
install -Dm644 "$THEME_DIR/waybar/style.css"         "$CFG/waybar/style.css"
install -Dm644 "$THEME_DIR/foot/foot.ini"            "$CFG/foot/foot.ini"
install -Dm644 "$THEME_DIR/fuzzel/fuzzel.ini"        "$CFG/fuzzel/fuzzel.ini"
install -Dm644 "$THEME_DIR/mako/config"              "$CFG/mako/config"
install -Dm644 "$THEME_DIR/kitty/theme-crt.conf"     "$CFG/kitty/theme-crt.conf"

touch "$CFG/kitty/kitty.conf"
grep -q '^include theme-crt.conf' "$CFG/kitty/kitty.conf" \
    || echo 'include theme-crt.conf' >> "$CFG/kitty/kitty.conf"
grep -q "$MARK\$" "$HYPR_CONF" || printf '\n%s %s\n' "$SOURCE_LINE" "$MARK" >> "$HYPR_CONF"

# Dark GTK apps (Thunar, file dialogs) to match.
gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark' 2>/dev/null || true
gsettings set org.gnome.desktop.interface gtk-theme 'Adwaita-dark' 2>/dev/null || true

reload
echo "CRT theme applied. SUPER+SHIFT+S toggles the screen effect."
echo "Tune scanlines, glow, green tint and curvature in $CFG/hypr/shaders/crt.frag"
