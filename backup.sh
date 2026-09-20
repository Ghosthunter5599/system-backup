#!/usr/bin/env bash
# ==============================================================================
# Omarchy & System Configuration Full Backup Script
# Creates a self-contained, restorable snapshot of all OS sizing, style,
# themes, dotfiles, configs, and package manifests.
# ==============================================================================

set -euo pipefail

BACKUP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIGS_DIR="$BACKUP_DIR/dotconfig"
DOTFILES_DIR="$BACKUP_DIR/dotfiles"
LOCAL_SHARE_DIR="$BACKUP_DIR/local_share"
THEMES_WALLPAPERS_DIR="$BACKUP_DIR/themes_and_wallpapers"
PKG_DIR="$BACKUP_DIR/packages"
METADATA_FILE="$BACKUP_DIR/system_state.json"

echo "======================================================="
echo " Starting System Configuration & Style Backup"
echo " Target Directory: $BACKUP_DIR"
echo "======================================================="

# Ensure target directories exist
mkdir -p "$CONFIGS_DIR" "$DOTFILES_DIR" "$LOCAL_SHARE_DIR" "$THEMES_WALLPAPERS_DIR" "$PKG_DIR"

# ------------------------------------------------------------------------------
# 1. Capture Installed Packages & Systemd Units
# ------------------------------------------------------------------------------
echo "[1/6] Exporting installed package lists & service states..."

if command -v pacman &>/dev/null; then
    pacman -Qqen > "$PKG_DIR/pacman_explicit_native.txt" || true
    pacman -Qqem > "$PKG_DIR/pacman_explicit_aur.txt" || true
    pacman -Qqe > "$PKG_DIR/all_explicit_packages.txt" || true
fi

if command -v flatpak &>/dev/null; then
    flatpak list --app --columns=application > "$PKG_DIR/flatpak_apps.txt" 2>/dev/null || true
fi

if command -v systemctl &>/dev/null; then
    systemctl --user list-unit-files --state=enabled --no-legend > "$PKG_DIR/systemd_user_enabled.txt" 2>/dev/null || true
    systemctl list-unit-files --state=enabled --no-legend > "$PKG_DIR/systemd_system_enabled.txt" 2>/dev/null || true
fi

# ------------------------------------------------------------------------------
# 2. Capture User Dotfiles from HOME
# ------------------------------------------------------------------------------
echo "[2/6] Backing up home shell & environment dotfiles..."
for file in .bashrc .bash_profile .bash_logout .zshrc .profile .XCompose .gitconfig; do
    if [ -f "$HOME/$file" ]; then
        cp -a "$HOME/$file" "$DOTFILES_DIR/"
    fi
done

# ------------------------------------------------------------------------------
# 3. Capture ~/.config directories (Window manager, themes, UI, apps)
# ------------------------------------------------------------------------------
echo "[3/6] Backing up ~/.config (Hyprland, Omarchy, Terminals, Styling)..."

# Comprehensive list of configuration targets
CONFIG_DIRS=(
    "hypr"
    "omarchy"
    "alacritty"
    "foot"
    "kitty"
    "ghostty"
    "starship.toml"
    "fastfetch"
    "btop"
    "nvim"
    "tmux"
    "git"
    "gtk-3.0"
    "gtk-4.0"
    "fontconfig"
    "dconf"
    "mimeapps.list"
    "environment.d"
    "autostart"
    "imv"
    "mpv"
    "obsidian"
    "obs-studio"
    "OpenRGB"
    "Pinta"
    "user-dirs.dirs"
    "uwsm"
    "wireplumber"
    "xdg-terminals.list"
    "fcitx5"
    "fcitx"
    "ibus"
    "pulse"
    "pavucontrol.ini"
    "QtProject.conf"
    "kdenliverc"
    "glow"
    "cliamp"
    "herdr"
    "xournalpp"
    "hyprland-preview-share-picker"
    "Omacom"
)

for item in "${CONFIG_DIRS[@]}"; do
    if [ -e "$HOME/.config/$item" ]; then
        # Exclude rust target build caches inside quickshell.spotify to save massive space
        rsync -a --delete \
            --exclude='quickshell.spotify/backend/target' \
            --exclude='*.log' \
            --exclude='*.sock' \
            --exclude='.git' \
            "$HOME/.config/$item" "$CONFIGS_DIR/"
    fi
done

# Copy any browser flag files
for flagfile in "$HOME"/.config/*-flags.conf; do
    if [ -f "$flagfile" ]; then
        cp -a "$flagfile" "$CONFIGS_DIR/"
    fi
done

# ------------------------------------------------------------------------------
# 4. Capture Local Share Assets (Fonts, Icons)
# ------------------------------------------------------------------------------
echo "[4/6] Backing up custom fonts & icons..."
if [ -d "$HOME/.local/share/fonts" ]; then
    rsync -a --delete --exclude='.git' "$HOME/.local/share/fonts" "$LOCAL_SHARE_DIR/"
fi
if [ -d "$HOME/.local/share/icons" ]; then
    rsync -a --delete --exclude='.git' "$HOME/.local/share/icons" "$LOCAL_SHARE_DIR/"
fi

# ------------------------------------------------------------------------------
# 5. Capture Wallpapers & Theme Media
# ------------------------------------------------------------------------------
echo "[5/6] Backing up Theme files and wallpapers..."
if [ -d "$HOME/Theme" ]; then
    rsync -a --delete --exclude='.git' "$HOME/Theme" "$THEMES_WALLPAPERS_DIR/"
fi

# ------------------------------------------------------------------------------
# 6. Capture State Metadata
# ------------------------------------------------------------------------------
echo "[6/6] Writing state metadata..."
CURRENT_THEME="Osaka Jade"
if [ -f "$HOME/.config/omarchy/current/theme.name" ]; then
    CURRENT_THEME=$(cat "$HOME/.config/omarchy/current/theme.name")
fi

cat <<STATE_EOF > "$METADATA_FILE"
{
  "backup_date": "$(date -Iseconds)",
  "hostname": "$(hostname 2>/dev/null || echo 'unknown')",
  "user": "$USER",
  "omarchy_theme": "$CURRENT_THEME",
  "display_config": "$HOME/.config/omarchy/displays.json",
  "hypr_looknfeel": "$HOME/.config/hypr/looknfeel.lua"
}
STATE_EOF

chmod +x "$BACKUP_DIR/backup.sh"

echo "======================================================="
echo " Backup completed successfully!"
echo " Location: $BACKUP_DIR"
echo "======================================================="
