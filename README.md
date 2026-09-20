# System Configuration & Desktop Style Backup

This backup contains everything required to return your Omarchy / Arch Linux system to its exact current state—including all UI sizing, styling, themes, keybindings, fonts, wallpapers, and installed packages—by running a single script.

---

## 🚀 How to Restore on a Fresh / Reinstalled OS

### 1. Extract the backup folder (if using the `.tar.gz` archive)
```bash
tar -xzf system-config-backup.tar.gz
cd system-config-backup
```

### 2. Run the restore script
```bash
chmod +x restore.sh
./restore.sh
```

### Options:
- **Full restore (packages + configs + styling + themes)**:
  ```bash
  ./restore.sh
  ```
- **Config & style only (skip package installations)**:
  ```bash
  ./restore.sh --skip-packages
  ```

---

## 🔄 How to Update the Backup in the Future

Whenever you make new customizations, you can update your backup snapshot by running:
```bash
cd ~/system-config-backup
./backup.sh
```

---

## 📁 What is Included in this Backup

1. **Window Manager & Desktop Sizing / Styling**:
   - `~/.config/hypr/` (Monitors, keybindings, window rules, animations, look'n'feel, gaps, rounding)
   - `~/.config/omarchy/` (Bar layout, plugins, custom themes, displays configuration)
2. **Terminal Configurations**:
   - Alacritty, Kitty, Foot, Ghostty
3. **Shell & Dotfiles**:
   - `.bashrc`, `.bash_profile`, `.zshrc`, Starship prompt (`starship.toml`), `.XCompose`
4. **Desktop Themes & Wallpapers**:
   - All custom Omarchy themes (`3-bat`, `akaito`, `ame-quattro`, `bat2`, `bat-fire`, `batred`, `coppernight`, `my-theme`, `rainynight`, `shadesofjade`)
   - Active Theme: **Osaka Jade**
   - Wallpaper directory (`~/Theme`)
   - Custom fonts (`~/.local/share/fonts`) and icons (`~/.local/share/icons`)
5. **App Configs & CLI Tools**:
   - Neovim, Fastfetch, Btop, Tmux, Git, OpenRGB, Obsidian, Obs-Studio, GTK 3/4, Dconf, etc.
6. **Package Manifests**:
   - Native Pacman explicit packages
   - AUR explicit packages
   - Enabled systemd services
