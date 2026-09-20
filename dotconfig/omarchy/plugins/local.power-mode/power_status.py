#!/usr/bin/env python3
import subprocess
import json

try:
    p = subprocess.run(["power-mode", "--json"], capture_output=True, text=True, timeout=2)
    data = json.loads(p.stdout)
    profile = data.get("active_profile", "custom").upper()
    gpu_w = data.get("gpu_power_limit", "N/A").replace(".00 W", "W").replace(" W", "W")
    cpu_w = f"{data.get('cpu_pl1_w', 0)}W"
    
    icon_map = {
        "GPU": "󰢮",
        "CACHY": "󰓅",
        "BALANCED": "󰗑",
        "CPU": "",
        "CUSTOM": "⚙️"
    }
    icon = icon_map.get(profile, "⚡")
    text = f"{icon} {profile} ({cpu_w}/{gpu_w})"
    
    tooltip = (
        f"⚡ Power Profile: {profile}\n"
        f"Description: {data.get('profile_name')}\n"
        f"─────────────────────────────\n"
        f"CPU Sustained (PL1): {data.get('cpu_pl1_w')} W\n"
        f"CPU Burst (PL2): {data.get('cpu_pl2_w')} W\n"
        f"CPU Governor/EPP: {data.get('cpu_epp')}\n"
        f"GPU Power Draw: {data.get('gpu_power_draw')}\n"
        f"GPU Power Limit: {data.get('gpu_power_limit')}\n"
        f"GPU Temperature: {data.get('gpu_temp')}\n"
        f"─────────────────────────────\n"
        f"Left Click: Open Power Mode TUI\n"
        f"Right Click: Cycle Profiles"
    )
    print(json.dumps({"text": text, "tooltip": tooltip}))
except Exception as e:
    print(json.dumps({"text": "⚡ Power", "tooltip": str(e)}))
