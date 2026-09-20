#!/usr/bin/env bash
# ==============================================================================
# Omarchy & System Configuration One-Click Restore Script
# Restores all OS styling, window manager sizing, themes, dotfiles, configs,
# fonts, wallpapers, and installed packages.
# ==============================================================================

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIGS_DIR="$SCRIPT_DIR/dotconfig"
DOTFILES_DIR="$SCRIPT_DIR/dotfiles"
LOCAL_SHARE_DIR="$SCRIPT_DIR/local_share"
THEMES_WALLPAPERS_DIR="$SCRIPT_DIR/themes_and_wallpapers"
PKG_DIR="$SCRIPT_DIR/packages"
METADATA_FILE="$SCRIPT_DIR/system_state.json"
BACKUP_TIMESTAMP="$(date +%Y%m%d_%H%M%S)"

# Text styling
BOLD='\033[1m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BOLD}${BLUE}=======================================================${NC}"
echo -e "${BOLD}${GREEN}   System Configuration & Style One-Click Restorer   ${NC}"
echo -e "${BOLD}${BLUE}=======================================================${NC}"

# Parse optional arguments
INSTALL_PKGS=true
for arg in "$@"; do
    case $arg in
        --no-packages|--skip-packages)
            INSTALL_PKGS=false
            shift
            ;;
    esac
done

# ------------------------------------------------------------------------------
# 1. Package Installation
# ------------------------------------------------------------------------------
if [ "$INSTALL_PKGS" = true ]; then
    echo -e "\n${BOLD}[1/5] Checking and Installing System Packages...${NC}"

    if command -v pacman &>/dev/null; then
        # Ensure base dependencies
        sudo pacman -S --needed --noconfirm base-devel git rsync

        # Install native packages
        if [ -f "$PKG_DIR/pacman_explicit_native.txt" ]; then
            echo -e "${BLUE}==> Installing native Pacman packages...${NC}"
            # Filter out any non-existent packages gracefully
            grep -v '^\s*$' "$PKG_DIR/pacman_explicit_native.txt" | while read -r pkg; do
                if pacman -Si "$pkg" &>/dev/null; then
                    echo "$pkg"
                fi
            done > /tmp/valid_native_pkgs.txt || true

            if [ -s /tmp/valid_native_pkgs.txt ]; then
                sudo pacman -S --needed --noconfirm - < /tmp/valid_native_pkgs.txt || true
            fi
            rm -f /tmp/valid_native_pkgs.txt
        fi

        # Check for AUR Helper (yay / paru)
        AUR_HELPER=""
        if command -v yay &>/dev/null; then
            AUR_HELPER="yay"
        elif command -v paru &>/dev/null; then
            AUR_HELPER="paru"
        else
            echo -e "${YELLOW}==> AUR helper not found. Installing yay-bin...${NC}"
            YAY_TMP="$(mktemp -d)"
            git clone https://aur.archlinux.org/yay-bin.git "$YAY_TMP/yay-bin"
            (cd "$YAY_TMP/yay-bin" && makepkg -si --noconfirm)
            rm -rf "$YAY_TMP"
            AUR_HELPER="yay"
        fi

        # Install AUR packages
        if [ -n "$AUR_HELPER" ] && [ -f "$PKG_DIR/pacman_explicit_aur.txt" ]; then
            echo -e "${BLUE}==> Installing AUR packages with $AUR_HELPER...${NC}"
            grep -v '^\s*$' "$PKG_DIR/pacman_explicit_aur.txt" | while read -r pkg; do
                echo -e "Installing AUR package: $pkg"
                "$AUR_HELPER" -S --needed --noconfirm "$pkg" || true
            done
        fi
    else
        echo -e "${YELLOW}Notice: 'pacman' not found. Skipping package installations.${NC}"
    fi
else
    echo -e "\n${YELLOW}[1/5] Skipping package installation as requested (--skip-packages).${NC}"
fi

# ------------------------------------------------------------------------------
# 2. Restore User Dotfiles in $HOME
# ------------------------------------------------------------------------------
echo -e "\n${BOLD}[2/5] Restoring Shell & Environment Dotfiles to $HOME...${NC}"
if [ -d "$DOTFILES_DIR" ]; then
    mkdir -p "$HOME/.dotfiles_backup_$BACKUP_TIMESTAMP"
    for file in "$DOTFILES_DIR"/.*; do
        base_name="$(basename "$file")"
        if [ "$base_name" != "." ] && [ "$base_name" != ".." ]; then
            if [ -e "$HOME/$base_name" ]; then
                cp -a "$HOME/$base_name" "$HOME/.dotfiles_backup_$BACKUP_TIMESTAMP/"
            fi
            cp -a "$file" "$HOME/$base_name"
            echo -e "  Restored $base_name"
        fi
    done
fi

# ------------------------------------------------------------------------------
# 3. Restore ~/.config Directory
# ------------------------------------------------------------------------------
echo -e "\n${BOLD}[3/5] Restoring ~/.config (Sizing, Styling, Hyprland & Shell)...${NC}"
mkdir -p "$HOME/.config"
if [ -d "$CONFIGS_DIR" ]; then
    for item in "$CONFIGS_DIR"/*; do
        if [ -e "$item" ]; then
            base_item="$(basename "$item")"
            if [ -e "$HOME/.config/$base_item" ]; then
                # Safe backup of existing item
                mkdir -p "$HOME/.config_backup_$BACKUP_TIMESTAMP"
                cp -a "$HOME/.config/$base_item" "$HOME/.config_backup_$BACKUP_TIMESTAMP/"
            fi
            rsync -a "$item" "$HOME/.config/"
            echo -e "  Restored config: $base_item"
        fi
    done
fi

# ------------------------------------------------------------------------------
# 4. Restore Fonts, Icons, Themes & Wallpapers
# ------------------------------------------------------------------------------
echo -e "\n${BOLD}[4/5] Restoring Fonts, Icons, Themes & Wallpapers...${NC}"

# Fonts & Icons
if [ -d "$LOCAL_SHARE_DIR/fonts" ]; then
    mkdir -p "$HOME/.local/share/fonts"
    rsync -a "$LOCAL_SHARE_DIR/fonts/" "$HOME/.local/share/fonts/"
    if command -v fc-cache &>/dev/null; then
        echo -e "  Refreshing font cache..."
        fc-cache -f "$HOME/.local/share/fonts" 2>/dev/null || true
    fi
fi

if [ -d "$LOCAL_SHARE_DIR/icons" ]; then
    mkdir -p "$HOME/.local/share/icons"
    rsync -a "$LOCAL_SHARE_DIR/icons/" "$HOME/.local/share/icons/"
fi

# Wallpapers & Theme directory
if [ -d "$THEMES_WALLPAPERS_DIR/Theme" ]; then
    mkdir -p "$HOME/Theme"
    rsync -a "$THEMES_WALLPAPERS_DIR/Theme/" "$HOME/Theme/"
    echo -e "  Restored ~/Theme directory."
fi

# ------------------------------------------------------------------------------
# 5. Re-apply Theme & Refresh Desktop State
# ------------------------------------------------------------------------------
echo -e "\n${BOLD}[5/5] Re-applying Theme & Desktop State...${NC}"

TARGET_THEME="Osaka Jade"
if [ -f "$METADATA_FILE" ] && command -v jq &>/dev/null; then
    TARGET_THEME="$(jq -r '.omarchy_theme // "Osaka Jade"' "$METADATA_FILE")"
elif [ -f "$HOME/.config/omarchy/current/theme.name" ]; then
    TARGET_THEME="$(cat "$HOME/.config/omarchy/current/theme.name")"
fi

if command -v omarchy &>/dev/null; then
    echo -e "${BLUE}==> Applying Omarchy theme: ${BOLD}$TARGET_THEME${NC}..."
    omarchy theme set "$TARGET_THEME" 2>/dev/null || true
    omarchy restart shell 2>/dev/null || true
    omarchy restart terminal 2>/dev/null || true
fi

if command -v hyprctl &>/dev/null; then
    echo -e "${BLUE}==> Reloading Hyprland config...${NC}"
    hyprctl reload 2>/dev/null || true
fi

# Enable systemd user services
if [ -f "$PKG_DIR/systemd_user_enabled.txt" ] && command -v systemctl &>/dev/null; then
    echo -e "${BLUE}==> Re-enabling systemd user services...${NC}"
    while read -r service _; do
        if [ -n "$service" ] && [[ "$service" == *.service || "$service" == *.socket ]]; then
            systemctl --user enable "$service" 2>/dev/null || true
        fi
    done < "$PKG_DIR/systemd_user_enabled.txt"
fi

echo -e "\n${BOLD}${GREEN}=======================================================${NC}"
echo -e "${BOLD}${GREEN}  Restore complete! All sizing, styling & configs set. ${NC}"
echo -e "${BOLD}${BLUE}=======================================================${NC}\n"
