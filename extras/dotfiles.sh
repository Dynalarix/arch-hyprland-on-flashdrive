#!/usr/bin/env bash
# Install someone's Hyprland dotfiles ("rice") from a git repo.
#
#   ./dotfiles.sh https://codeberg.org/zacoons/astroland_dots
#
# Run as your normal user (uses sudo for packages), or as root with
# TARGET_USER=name (the installer does this). Existing config folders that get
# replaced are backed up to ~/.config/dotfiles-backup-<date>/.
set -euo pipefail

REPO="${1:?usage: $0 <git url>}"
TARGET_USER="${TARGET_USER:-$(id -un)}"
HOME_DIR="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
[[ -n "$HOME_DIR" ]] || { echo "no such user $TARGET_USER" >&2; exit 1; }
if [[ $EUID -eq 0 ]]; then SUDO=(); else SUDO=(sudo); fi
as_user() { if [[ $EUID -eq 0 ]]; then runuser -u "$TARGET_USER" -- "$@"; else "$@"; fi; }

log() { printf '\033[1;32m==>\033[0m %s\n' "$*"; }

name="$(basename "${REPO%.git}")"
SRC="$HOME_DIR/.local/share/dotfiles/$name"
CFG="$HOME_DIR/.config"
BACKUP="$CFG/dotfiles-backup-$(date +%Y%m%d-%H%M%S)"

log "Fetching $REPO"
as_user mkdir -p "$(dirname "$SRC")"
if [[ -d "$SRC/.git" ]]; then as_user git -C "$SRC" pull --ff-only
else as_user git clone --depth 1 "$REPO" "$SRC"; fi

# Packages the rice lists, if it ships a list. Unknown names are skipped.
for list in "$SRC"/{packages,pkglist,pkgs,dependencies,deps}{,.txt}; do
    [[ -f "$list" ]] || continue
    log "Installing packages from $(basename "$list")"
    mapfile -t want < <(sed -e 's/#.*//' -e 's/[[:space:]]\+/\n/g' "$list" | sed '/^$/d')
    ok=()
    for p in "${want[@]}"; do pacman -Si "$p" &>/dev/null && ok+=("$p") || echo "  skipping $p (not in repos, maybe AUR)"; done
    ((${#ok[@]})) && "${SUDO[@]}" pacman -S --needed --noconfirm "${ok[@]}"
done

# Work out where the config folders live in the repo.
if   [[ -d "$SRC/.config" ]]; then from="$SRC/.config"
elif [[ -d "$SRC/config"  ]]; then from="$SRC/config"
elif [[ -d "$SRC/dotconfig" ]]; then from="$SRC/dotconfig"
else from="$SRC"; fi

skip='^(\.git|\.github|assets|screenshots?|images?|docs?|preview|wallpapers?|walls|fonts|bin|scripts|\.local|config|\.config)$'
copied=()
for dir in "$from"/*/ "$from"/.[!.]*/; do
    [[ -d "$dir" ]] || continue
    n="$(basename "$dir")"
    [[ "$from" == "$SRC" && "$n" =~ $skip ]] && continue
    [[ "$n" =~ ^\.git ]] && continue
    if [[ -e "$CFG/$n" ]]; then
        as_user mkdir -p "$BACKUP"
        as_user cp -a "$CFG/$n" "$BACKUP/"
        rm -rf "${CFG:?}/$n"
    fi
    as_user cp -a "$dir" "$CFG/$n"
    copied+=("$n")
done
[[ -d "$SRC/.local" ]] && as_user cp -a "$SRC/.local/." "$HOME_DIR/.local/"
for w in wallpapers wallpaper walls; do
    [[ -d "$SRC/$w" ]] && { as_user mkdir -p "$HOME_DIR/Pictures"; as_user cp -a "$SRC/$w" "$HOME_DIR/Pictures/"; }
done
for f in "$SRC"/fonts/*.{ttf,otf}; do
    [[ -f "$f" ]] || continue
    as_user mkdir -p "$HOME_DIR/.local/share/fonts"; as_user cp "$f" "$HOME_DIR/.local/share/fonts/"
done
command -v fc-cache >/dev/null && as_user fc-cache -f >/dev/null 2>&1 || true

log "Installed into ~/.config: ${copied[*]:-nothing}"
[[ -d "$BACKUP" ]] && log "Your previous folders are in $BACKUP"
for s in install.sh setup.sh; do
    [[ -f "$SRC/$s" ]] && log "The repo also has its own $s; read it in $SRC before running it."
done
exit 0
