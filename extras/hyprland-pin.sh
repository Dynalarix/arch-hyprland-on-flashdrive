#!/usr/bin/env bash
# Install a specific Hyprland version from the Arch Linux Archive and keep
# pacman from upgrading it.
#
#   sudo ./hyprland-pin.sh 0.55.2    install and pin Hyprland 0.55.2
#   sudo ./hyprland-pin.sh --unpin   remove the pin and update to the latest
#
# Hyprland and its own libraries (aquamarine, hyprutils, hyprlang, ...) and
# the other hypr* tools you have installed (hyprlock, hypridle, portal, ...)
# are all taken from the same archive snapshot, so they match each other.
set -euo pipefail

ARCHIVE="https://archive.archlinux.org"
MARK="# hyprland-pin: managed by hyprland-pin.sh"
PIN_RE='^(hyprland|aquamarine|hypr[a-z0-9-]*|xdg-desktop-portal-hyprland)$'

die()  { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }
log()  { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mwarning:\033[0m %s\n' "$*" >&2; }

[[ $EUID -eq 0 ]] || die "run with sudo"
[[ $# -eq 1 ]] || die "usage: $0 <version> | --unpin"

unpin() { sed -i "/^$MARK\$/{N;d}" /etc/pacman.conf; }

if [[ "$1" == "--unpin" ]]; then
    unpin
    log "Pin removed. Updating to the latest Hyprland..."
    pacman -Syu --noconfirm
    exit 0
fi

VER="$1"
[[ "$VER" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "version should look like 0.55.2"

if [[ "$(pacman -Q hyprland 2>/dev/null | awk '{print $2}')" == "$VER"-* ]]; then
    log "Hyprland $VER is already installed"
    already=1
else
    already=0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

if (( !already )); then
    log "Looking up Hyprland $VER in the Arch Linux Archive"
    listing="$(curl -fsSL "$ARCHIVE/packages/h/hyprland/")" || die "cannot reach $ARCHIVE"
    file="$(grep -oE "hyprland-$VER-[0-9.]+-x86_64\.pkg\.tar\.zst" <<<"$listing" | sort -uV | tail -n1)"
    [[ -n "$file" ]] || die "Hyprland $VER is not in the archive. Versions there: $(grep -oE 'hyprland-[0-9.]+-' <<<"$listing" | sort -uV | tr '\n' ' ')"
    built="$(grep -F "$file\"" <<<"$listing" | grep -oE '[0-9]{2}-[A-Za-z]{3}-[0-9]{4}' | head -n1)"
    [[ -n "$built" ]] || die "cannot read the date of $file"

    # The daily repo snapshot from right after that build has 0.55.2 together
    # with the matching versions of its libraries.
    mkdir -p "$TMP/db/local" "$TMP/pkgs"
    others=()
    while read -r p; do [[ "$p" == hyprland ]] || others+=("$p"); done \
        < <(pacman -Qq | grep -E "$PIN_RE" || true)
    found=""
    for offset in 0 1 2 3 4 5 6 7 10 14 21; do
        snap="$(date -d "$built + $offset day" +%Y/%m/%d)"
        cat > "$TMP/pacman.conf" <<CONF
[options]
Architecture = x86_64
SigLevel = Never
[core]
Server = $ARCHIVE/repos/$snap/\$repo/os/\$arch
[extra]
Server = $ARCHIVE/repos/$snap/\$repo/os/\$arch
CONF
        P=(pacman --config "$TMP/pacman.conf" --dbpath "$TMP/db" --noconfirm)
        "${P[@]}" -Sy >/dev/null 2>&1 || continue
        v="$("${P[@]}" -Sp --print-format '%v' hyprland 2>/dev/null | tail -n1 || true)"
        log "Snapshot $snap has hyprland $v"
        if [[ "$v" == "$VER"-* ]]; then found="$snap"; break; fi
    done
    [[ -n "$found" ]] || die "no archive snapshot with Hyprland $VER found"

    # Resolve hyprland + the hypr* tools installed here, keep only the hypr
    # family (everything else, like mesa or qt, stays at the current version).
    targets=(hyprland)
    for p in "${others[@]}"; do
        if "${P[@]}" -Sp "$p" >/dev/null 2>&1; then targets+=("$p")
        else warn "$p did not exist in that snapshot; leaving the current version"; fi
    done
    mapfile -t urls < <("${P[@]}" -Sp --print-format '%n %l' "${targets[@]}" \
        | awk -v re="$PIN_RE" '$1 ~ re {print $2}' | sort -u)
    ((${#urls[@]})) || die "nothing to download"

    log "Downloading ${#urls[@]} packages from snapshot $found"
    for u in "${urls[@]}"; do
        curl -fsSL --retry 3 -o "$TMP/pkgs/$(basename "$u")" "$u"
        curl -fsSL --retry 3 -o "$TMP/pkgs/$(basename "$u").sig" "$u.sig" || true
    done

    log "Installing (signatures are checked against your pacman keyring)"
    pacman -U --noconfirm "$TMP"/pkgs/*.pkg.tar.zst
fi

# Pin every hypr-family package now installed.
mapfile -t pinned < <(pacman -Qq | grep -E "$PIN_RE")
unpin
sed -i "/^\[options\]/a $MARK\nIgnorePkg = ${pinned[*]}" /etc/pacman.conf
log "Pinned: ${pinned[*]}"

# Older Hyprland built against libraries that have moved on since?
if missing="$(ldd /usr/bin/Hyprland 2>/dev/null | grep 'not found')"; then
    warn "Hyprland $VER is missing system libraries on this system:"
    echo "$missing" >&2
    warn "It won't start like this. Run '$0 --unpin' to go back to the latest version."
    exit 1
fi
log "Hyprland $VER is installed and pinned. 'pacman -Syu' will skip it."
