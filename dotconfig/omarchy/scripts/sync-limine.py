#!/usr/bin/env python3
import sys
import os
import glob
import tomllib

def find_colors_path():
    # 1. Check command line argument
    if len(sys.argv) > 1 and os.path.isfile(sys.argv[1]):
        return sys.argv[1]

    # 2. Check TARGET_HOME env var
    target_home = os.environ.get("TARGET_HOME")
    if target_home:
        path = os.path.join(target_home, ".local/state/omarchy/current/theme/colors.toml")
        if os.path.isfile(path):
            return path

    # 3. Check current user HOME
    home = os.environ.get("HOME")
    if home:
        path = os.path.join(home, ".local/state/omarchy/current/theme/colors.toml")
        if os.path.isfile(path):
            return path

    # 4. Fallback search /home/*
    matches = glob.glob("/home/*/.local/state/omarchy/current/theme/colors.toml")
    if matches:
        return matches[0]

    return None

def sync_limine():
    colors_path = find_colors_path()
    if not colors_path or not os.path.isfile(colors_path):
        print(f"Error: colors.toml not found (checked args, env, /home/*)", file=sys.stderr)
        return 1

    try:
        with open(colors_path, "rb") as f:
            colors = tomllib.load(f)
    except Exception as e:
        print(f"Error reading {colors_path}: {e}", file=sys.stderr)
        return 1

    def clean(key, fallback="ffffff"):
        val = colors.get(key, fallback)
        return str(val).lstrip("#")

    accent = clean("accent", "7aa2f7")
    help_col = clean("light_foreground", clean("foreground", "c0caf5"))
    bg = clean("background", "1a1b26")
    backdrop = clean("darker_background", bg)
    bg_bright = clean("lighter_background", bg)
    fg = clean("foreground", "c0caf5")
    fg_bright = clean("bright_foreground", fg)

    palette = [
        clean("dark_background", "15161e"),
        clean("red", "f7768e"),
        clean("green", "9ece6a"),
        clean("yellow", "e0af68"),
        clean("blue", "7aa2f7"),
        clean("magenta", "bb9af7"),
        clean("cyan", "7dcfff"),
        clean("foreground", "a9b1d6")
    ]

    bright_palette = [
        clean("muted", "414868"),
        clean("bright_red", clean("red", "f7768e")),
        clean("bright_green", clean("green", "9ece6a")),
        clean("bright_yellow", clean("yellow", "e0af68")),
        clean("bright_blue", clean("blue", "7aa2f7")),
        clean("bright_magenta", clean("magenta", "bb9af7")),
        clean("bright_cyan", clean("cyan", "7dcfff")),
        clean("bright_foreground", clean("foreground", "c0caf5"))
    ]

    header = f"""### Read more at config document: https://github.com/limine-bootloader/limine/blob/trunk/CONFIG.md
#timeout: 3
default_entry: 2
interface_branding: Omarchy Bootloader
interface_branding_color: {accent}
interface_help_color: {help_col}
interface_help_color_bright: {accent}
hash_mismatch_panic: no

term_background: {bg}
backdrop: {backdrop}

# Terminal colors (Theme palette)
term_palette: {";".join(palette)}
term_palette_bright: {";".join(bright_palette)}

# Text colors
term_foreground: {fg}
term_foreground_bright: {fg_bright}
term_background_bright: {bg_bright}
"""

    limine_conf_path = "/boot/limine.conf"
    entries = ""
    if os.path.isfile(limine_conf_path):
        with open(limine_conf_path, "r", encoding="utf-8") as f:
            content = f.read()
        pos = content.find("\n/+")
        if pos == -1:
            pos = content.find("\n/")
        if pos != -1:
            entries = content[pos+1:]
        elif content.startswith("/+") or content.startswith("/"):
            entries = content

    if not entries:
        print("Warning: No boot entries found in /boot/limine.conf, aborting", file=sys.stderr)
        return 1

    new_content = header.strip() + "\n" + entries.strip() + "\n"

    temp_path = "/boot/limine.conf.tmp"
    try:
        with open(temp_path, "w", encoding="utf-8") as f:
            f.write(new_content)
        os.replace(temp_path, limine_conf_path)
        print("Successfully synchronized theme colors to /boot/limine.conf")
        return 0
    except Exception as e:
        print(f"Error writing to /boot/limine.conf: {e}", file=sys.stderr)
        return 1

if __name__ == "__main__":
    sys.exit(sync_limine())
