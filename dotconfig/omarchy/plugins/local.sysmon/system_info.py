#!/usr/bin/env python3
import psutil
import json
import shutil
import subprocess
import os

PARTITIONS = {"Root": "/"}

C = {
    "red": "#f38ba8", "peach": "#fab387", "yellow": "#f9e2af",
    "green": "#a6e3a1", "blue": "#89b4fa", "mauve": "#cba6f7", 
    "teal": "#94e2d5", "sky": "#89dceb", "lavender": "#b4befe",
    "subtext": "#a5adce", "surface": "#313244", "text": "#cdd6f4"
}

def fmt_size(bytes):
    for unit in ['B', 'KB', 'MB', 'GB', 'TB']:
        if bytes < 1024: return f"{bytes:.1f}{unit}"
        bytes /= 1024

def get_gpu_info():
    gpu = {"usage": 0, "active": False}
    try:
        res = subprocess.check_output(
            ["nvidia-smi", "--query-gpu=utilization.gpu", "--format=csv,noheader,nounits"], 
            encoding='utf-8', stderr=subprocess.DEVNULL
        )
        gpu.update({"usage": int(res.strip()), "active": True})
        return gpu
    except Exception:
        pass

    try:
        if os.path.exists("/sys/class/drm/card0/device/gpu_busy_percent"):
            with open("/sys/class/drm/card0/device/gpu_busy_percent", "r") as f:
                gpu["usage"] = int(f.read().strip())
                gpu["active"] = True
    except Exception:
        pass
    return gpu

def get_top_apps(n=5):
    apps = []
    for proc in psutil.process_iter(['pid', 'name', 'cpu_percent', 'memory_percent']):
        try:
            apps.append(proc.info)
        except (psutil.NoSuchProcess, psutil.AccessDenied):
            pass

    apps = sorted(apps, key=lambda x: x['memory_percent'] or 0, reverse=True)
    rows = []
    for a in apps[:n]:
        name = (a['name'][:12] + '..') if len(a['name']) > 13 else a['name']
        cpu = a['cpu_percent'] if a['cpu_percent'] else 0.0
        mem = a['memory_percent'] if a['memory_percent'] else 0.0
        rows.append(f"{a['pid']:<6} {name:<14} {cpu:>5.1f}% {mem:>5.1f}%")
    return "\n".join(rows)

def get_sys_info():
    cpu_usage = psutil.cpu_percent(interval=0.1)
    ram = psutil.virtual_memory()
    gpu = get_gpu_info()
    
    tt = f"SYSTEM MONITOR\n"
    tt += f"━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
    tt += f"CPU Load:   {cpu_usage:.1f}%\n"
    tt += f"RAM Used:   {fmt_size(ram.used)} / {fmt_size(ram.total)} ({ram.percent:.1f}%)\n"
    if gpu["active"]:
        tt += f"GPU Load:   {gpu['usage']}%\n"
        
    tt += f"────────────────────────────\n"
    tt += f"TOP APPS (BY RAM)\n"
    tt += get_top_apps(5)
    tt += f"\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
    tt += f"Click to launch btop"

    # Bar Text with Nerd Font icons
    gpu_bar = f"  󰢮 {gpu['usage']}%" if gpu['active'] else ""
    bar_text = f" {int(cpu_usage)}%  󰰠 {int(ram.percent)}%{gpu_bar}"

    return {"text": bar_text, "tooltip": tt}

if __name__ == "__main__":
    print(json.dumps(get_sys_info()))
