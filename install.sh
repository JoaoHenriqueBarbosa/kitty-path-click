#!/bin/bash
# Adds this repository to pacman (ahead of the official ones, so its kitty wins) and
# replaces the installed kitty packages with the patched build.
set -euo pipefail

REPO_NAME=kitty-path-click
SERVER=https://github.com/JoaoHenriqueBarbosa/kitty-path-click/releases/download/repo
CONF=/etc/pacman.conf

if ! grep -q "^\[$REPO_NAME\]" "$CONF"; then
    sudo cp "$CONF" "$CONF.bak-$(date +%s)"
    # Insert before the first repository section (the first [section] after [options])
    sudo awk -v name="$REPO_NAME" -v server="$SERVER" '
        !done && /^\[/ && $0 != "[options]" {
            print "[" name "]"
            # Packages are unsigned; trust comes from HTTPS to the GitHub release
            print "SigLevel = Optional TrustAll"
            print "Server = " server
            print ""
            done = 1
        }
        { print }
    ' "$CONF" | sudo tee "$CONF.new" >/dev/null
    sudo mv "$CONF.new" "$CONF"
fi

sudo pacman -Sy
sudo pacman -S --noconfirm "$REPO_NAME/kitty" "$REPO_NAME/kitty-terminfo" "$REPO_NAME/kitty-shell-integration"
pacman -Sl "$REPO_NAME"
