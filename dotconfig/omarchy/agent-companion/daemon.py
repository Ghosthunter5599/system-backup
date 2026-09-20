#!/usr/bin/env python3
import json
import os
import subprocess
import time
import glob

STATE_FILE = "/tmp/agent-companion-state.json"
GEMINI_BRAIN = os.path.expanduser("~/.gemini/antigravity-cli/brain")

def find_latest_transcript():
    try:
        jsonl_files = glob.glob(f"{GEMINI_BRAIN}/*/.system_generated/logs/transcript.jsonl")
        if not jsonl_files:
            return None
        latest = max(jsonl_files, key=os.path.getmtime)
        # Only consider active if modified within last 120 seconds
        if time.time() - os.path.getmtime(latest) < 180:
            return latest
    except Exception:
        pass
    return None

def check_cmd_process():
    try:
        out = subprocess.check_output(["pgrep", "-f", "node.*bin/cmd"]).decode().strip()
        return len(out) > 0
    except Exception:
        return False

def get_agy_status(transcript_path):
    if not transcript_path:
        return None
    try:
        with open(transcript_path, "r", encoding="utf-8") as f:
            lines = [l.strip() for l in f if l.strip()]
        if not lines:
            return None
        
        last_step = json.loads(lines[-1])
        step_type = last_step.get("type", "")
        status = last_step.get("status", "")
        tool_calls = last_step.get("tool_calls", [])
        
        # Check if modified very recently (within 45s)
        is_fresh = (time.time() - os.path.getmtime(transcript_path)) < 45
        
        if tool_calls and (status == "RUNNING" or is_fresh):
            tc = tool_calls[0]
            action = tc.get("toolAction") or tc.get("toolSummary") or "Executing tool"
            func_name = tc.get("function", {}).get("name", "tool")
            return {
                "agent": "agy",
                "state": "working",
                "title": "Guhan · AGY",
                "action": action,
                "subtext": f"Running {func_name}",
                "visible": True
            }
        elif is_fresh:
            return {
                "agent": "agy",
                "state": "thinking",
                "title": "Guhan · AGY",
                "action": "Analyzing codebase",
                "subtext": "Thinking...",
                "visible": True
            }
        else:
            return {
                "agent": "agy",
                "state": "idle",
                "title": "Guhan · AGY",
                "action": "Standing by",
                "subtext": "Task completed",
                "visible": True
            }
    except Exception as e:
        return None

def main():
    last_written = None
    while True:
        try:
            # 1. Check CMD first
            cmd_active = check_cmd_process()
            if cmd_active:
                state = {
                    "agent": "cmd",
                    "state": "working",
                    "title": "Guhan · CMD",
                    "action": "Executing command",
                    "subtext": "Running task...",
                    "visible": True
                }
            else:
                # 2. Check AGY
                latest_tr = find_latest_transcript()
                state = get_agy_status(latest_tr)
                if not state:
                    state = {
                        "agent": "agy",
                        "state": "idle",
                        "title": "Guhan · AGY",
                        "action": "Standing by",
                        "subtext": "Ready for orders",
                        "visible": True
                    }
            
            raw = json.dumps(state)
            if raw != last_written:
                with open(STATE_FILE + ".tmp", "w") as f:
                    f.write(raw)
                os.replace(STATE_FILE + ".tmp", STATE_FILE)
                last_written = raw
        except Exception:
            pass
        time.sleep(0.5)

if __name__ == "__main__":
    main()
