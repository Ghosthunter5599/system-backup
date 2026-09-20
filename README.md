# 🖥️ Arch Linux & Omarchy System Configuration Backup

A complete, self-contained snapshot and one-click restoration suite for Arch Linux / Omarchy. This repository preserves all system styling, window manager configurations, custom bar & widget plugins, terminal setups, shell environments, themes, wallpapers, and installed package manifests.

---

## 🚀 Quick Restoration Guide

### On a Fresh or Reinstalled Arch / Omarchy System:

1. **Clone the repository**:
   ```bash
   git clone https://github.com/Ghosthunter5599/system-backup.git ~/system-config-backup
   cd ~/system-config-backup
   ```

2. **Execute the one-click restorer**:
   ```bash
   chmod +x restore.sh
   ./restore.sh
   ```

### Restore Options:
- **Full Restoration** (Installs all native Pacman + AUR packages, restores all configs, dotfiles, themes, fonts, and re-applies current theme):
  ```bash
  ./restore.sh
  ```
- **Configuration & Style Only** (Skips package installation, restores dotfiles, desktop sizing, themes, and styling):
  ```bash
  ./restore.sh --skip-packages
  ```

---

## 🔄 Updating the Backup Snapshot

Whenever you modify keybindings, install new plugins, or tweak styling, update the backup snapshot with:
```bash
cd ~/system-config-backup
./backup.sh
git add -A
git commit -m "Update system configurations and package manifest"
git push origin main
```

---

## 🧩 Detailed System Breakdown

### 1. 🔌 Omarchy Plugins (Custom & Community)
All installed plugins are backed up under [`dotconfig/omarchy/plugins/`](dotconfig/omarchy/plugins/):

#### **Custom `b47m4n` Suite:**
- **`b47m4n.bar`**: Custom top bar layout, module order, layout spacing, and custom widget anchors.
- **`b47m4n.menu`**: Custom application launcher, system action menus, and categorized fast-launch grid.
- **`b47m4n.power`**: Session manager for shutdown, reboot, lock, suspend, and logout triggers.
- **`b47m4n.indicators`**: Custom tray & system indicator widgets (network, battery, audio, CPU/RAM).
- **`b47m4n.companion`**: Companion assistant widget for contextual system actions and shortcuts.
- **`b47m4n.agents`**: Autonomous agent management and companion dashboard integration.

#### **Community & Extension Plugins:**
- **`better.displays`**: Dynamic monitor profile switching, multi-display resolution & position orchestration.
- **`io.github.thetrueferret.decent-workspaces`**: Workspace visualization, active window icons, and dynamic workspace switcher.
- **`io.github.tuthan.dropdown-terminal`**: Quake-style drop-down terminal toggle with custom dimensions and animations.
- **`io.github.rawritude.simple-hotspot` & `io.github.shivamnarkar47.omarchy-hotspot`**: Wi-Fi Access Point creation, toggle, and QR code sharing.
- **`quickshell.spotify`**: Quickshell-based interactive Spotify & MPRIS media player controller.
- **`shavanced.notification-center`**: Notification center panel with history, quick toggles, and DND mode.
- **`shmall.lock`**: Hyprlock screen locking trigger integration.
- **`ssupt.audio-control`**: Audio device routing, volume slider popup, and sink switcher.
- **`local.warp`**: Cloudflare WARP VPN toggle and status widget.
- **`local.power-mode`**: CPU power profile governor switcher (Performance, Balanced, Power-saver).
- **`local.sysmon`**: Real-time CPU, RAM, GPU, and disk utilization monitor.
- **`nosignal.plugin-manager`**: Graphical plugin browser, updater, and installer.

---

### 2. 🪟 Window Manager & Desktop Styling (Hyprland)
Located under [`dotconfig/hypr/`](dotconfig/hypr/) and [`dotconfig/omarchy/`](dotconfig/omarchy/):

- **Keybindings (`bindings.lua` / `bindings.conf`)**:
  - `SUPER + Return` / `SUPER + Q`: Launch preferred terminal (Ghostty/Kitty).
  - `SUPER + Space`: Omarchy application menu / launcher.
  - `SUPER + Shift + S`: Omagrab screenshot utility.
  - Multi-workspace switching, floating tile toggles, split directions, and window resizing shortcuts.
- **Look & Feel (`looknfeel.lua` / `looknfeel.conf`)**:
  - Gaps (inner & outer), corner rounding, border thickness, active/inactive border gradients.
  - Hyprland window animations, bezier curves, and dual-kawase blur passes.
- **Displays & Monitors (`monitors.lua` / `displays.json`)**:
  - High-refresh rate monitor resolutions, scaling factors, refresh rates, and multi-monitor positioning coordinates.
- **Inputs & Gestures (`input.lua` / `input.conf`)**:
  - Keyboard repeat rates, mouse sensitivity, touchpad natural scrolling, multi-finger swipe gestures.
- **Lockscreen & Night Light (`hyprlock.conf`, `hypridle.conf`, `hyprsunset.conf`)**:
  - Custom lockscreen banner, font rendering, dynamic clock, quote engine (`quotes.txt`), idle screen sleep timers, and blue-light temperature schedules.

---

### 3. 💻 Terminals & Shell Environment

#### **Shell Configurations:**
- **Starship Prompt (`dotconfig/starship.toml`)**: Custom prompt styling with git status, execution time, directory truncation, node/python runtime indicators, and custom character glyphs.
- **Bash & Zsh (`dotfiles/.bashrc`, `.bash_profile`, `.zshrc`)**:
  - Environment variables, path exports (NVM, Rust/Cargo, Go, Local Binaries, Mise).
  - Aliases for fast navigation, git shortcuts, pacman/yay management, and system maintenance.
  - Musl dynamic relocation compatibility guards (`LD_PRELOAD` overrides).

#### **Terminal Emulators:**
- **Ghostty (`dotconfig/ghostty/`)**:
  - Primary high-performance terminal emulator.
  - Custom GLSL post-processing shaders (`dotconfig/ghostty/shaders/`).
  - True-color support, background opacity, font metrics, and keybindings.
- **Kitty (`dotconfig/kitty/kitty.conf`)**:
  - Font configurations (JetBrains Mono / Nerd Fonts), window padding, tab-bar styling, cursor effects.
- **Alacritty (`dotconfig/alacritty/alacritty.toml`)**:
  - GPU-accelerated minimalist terminal profile with custom window opacity and colorscheme definitions.
- **Foot (`dotconfig/foot/foot.ini`)**:
  - Ultra-fast Wayland native terminal configuration.

---

### 4. 🎨 Themes, Wallpapers & Assets
Located under [`dotconfig/omarchy/themes/`](dotconfig/omarchy/themes/) and [`themes_and_wallpapers/`](themes_and_wallpapers/):

- **Active Theme**: **Osaka Jade**
- **Theme Collection**:
  - `Osaka Jade`, `3-bat`, `akaito`, `ame-quattro`, `bat2`, `bat-fire`, `batred`, `coppernight`, `cyberpunk`, `latchdark`, `my-theme`, `phosphor-os`, `rainynight`, `shadesofjade`.
- **Motion Wallpapers & Scripts (`themes_and_wallpapers/Theme/`)**:
  - Animated & motion wallpaper daemon scripts (`wallpaper.sh`, `motion-wallpaper-theme-watcher`, `motion-wallpaper.service`).
  - Wallpaper packs, vector logos, and custom high-resolution backgrounds.
- **Fonts & Icons (`local_share/`)**:
  - Custom Nerd Fonts, symbol glyphs, desktop `.desktop` entries, and custom hicolor icon sets.

---

### 5. 🛠️ CLI & GUI Application Configs
- **Neovim (`dotconfig/nvim/`)**: Lua-based configuration, keybindings, LSP, syntax highlighting.
- **Fastfetch (`dotconfig/fastfetch/`)**: Custom ASCII art and system telemetry specs fetch.
- **Btop (`dotconfig/btop/`)**: Custom resource monitoring graph styling and theme palette.
- **Tmux (`dotconfig/tmux/`)**: Terminal multiplexer bindings, status bar format, pane navigation.
- **GTK & Theming (`dotconfig/gtk-3.0/`, `dotconfig/gtk-4.0/`, `dotconfig/fontconfig/`, `dotconfig/dconf/`)**: Uniform UI styling across GTK and Qt apps.
- **Creative & Productivity**: OBS Studio (`dotconfig/obs-studio/`), Obsidian (`dotconfig/obsidian/`), OpenRGB (`dotconfig/OpenRGB/`), Pinta, Xournalpp.

---

### 6. 📦 Package Manifests & Services
All package manifests are stored in [`packages/`](packages/):
- `pacman_explicit_native.txt`: Explicitly installed Arch repository packages.
- `pacman_explicit_aur.txt`: Explicitly installed AUR packages.
- `all_explicit_packages.txt`: Combined full explicit package manifest.
- `flatpak_apps.txt`: Flatpak application manifest.
- `systemd_user_enabled.txt` & `systemd_system_enabled.txt`: Automatically re-enabled system and user daemons upon restoration.

---

## 📜 Metadata & Snapshot State
Saved in [`system_state.json`](system_state.json):
```json
{
  "hostname": "omarchy",
  "user": "b47m4n",
  "omarchy_theme": "Osaka Jade"
}
```
