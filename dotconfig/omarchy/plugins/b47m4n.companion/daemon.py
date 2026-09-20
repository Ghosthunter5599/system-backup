#!/usr/bin/env python3
import json
import os
import subprocess
import time
import glob
import re

STATE_FILE = "/tmp/agent-companion-state.json"
CONFIG_FILE = os.path.expanduser("~/.config/omarchy/plugins/b47m4n.companion/config.json")
GEMINI_BRAIN = os.path.expanduser("~/.gemini/antigravity-cli/brain")
NAP_IDLE_SECONDS = 5.0  # Transition to nap after 5s of idle
DEFAULT_IDLE_TIMEOUT = 1800.0  # Disappear after 30 minutes of idle

def load_config():
    default_config = {
        "enabled": True,
        "idle_timeout": 1800
    }
    try:
        if os.path.exists(CONFIG_FILE):
            with open(CONFIG_FILE, "r") as f:
                cfg = json.load(f)
                return {**default_config, **cfg}
    except Exception:
        pass
    return default_config

def is_process_running(pattern):
    try:
        pids = subprocess.check_output(["pgrep", "-f", pattern]).decode().strip().split()
        return len(pids) > 0, pids
    except Exception:
        return False, []

def is_agy_running():
    try:
        pids = subprocess.check_output(["pgrep", "-x", "agy"]).decode().strip().split()
        if pids:
            return True, pids
    except Exception:
        pass
    try:
        pids = subprocess.check_output(["pgrep", "-f", r"(^|/)agy($|\s)"]).decode().strip().split()
        real_pids = []
        for pid in pids:
            try:
                with open(f"/proc/{pid}/cmdline", "rb") as f:
                    cmd = f.read().decode("utf-8", errors="ignore").replace("\0", " ").strip()
                if cmd.startswith("agy") or "/agy " in cmd or cmd.endswith("/agy") or cmd == "agy":
                    real_pids.append(pid)
            except Exception:
                pass
        return len(real_pids) > 0, real_pids
    except Exception:
        return False, []

def find_latest_transcript():
    try:
        jsonl_files = glob.glob(f"{GEMINI_BRAIN}/*/.system_generated/logs/transcript.jsonl")
        if not jsonl_files:
            return None
        return max(jsonl_files, key=os.path.getmtime)
    except Exception:
        return None

cmd_was_working = False
cmd_last_work_finish = 0
cmd_last_work_time = 0

def check_command_code_status(idle_timeout=DEFAULT_IDLE_TIMEOUT):
    global cmd_was_working, cmd_last_work_finish, cmd_last_work_time
    is_running, pids = is_process_running(r"(command-code|bin/cmd)")
    now = time.time()

    if not is_running:
        cmd_was_working = False
        return {
            "open": False,
            "active": False,
            "state": "idle",
            "action": "Standing by",
            "subtext": "Offline",
            "message": "Standing by."
        }

    # Find latest active project session file
    files = [f for f in glob.glob(os.path.expanduser("~/.commandcode/projects/*/*.jsonl")) if not f.endswith(".checkpoints.jsonl")]
    latest_file = max(files, key=os.path.getmtime) if files else None

    is_actively_writing = False
    last_thought = ""
    last_action = "Executing command"

    if latest_file:
        mtime = os.path.getmtime(latest_file)
        age = now - mtime
        if cmd_last_work_time == 0:
            cmd_last_work_time = mtime

        try:
            with open(latest_file, "r", encoding="utf-8") as f:
                lines = [l.strip() for l in f if l.strip()]
            if lines:
                last_entry = json.loads(lines[-1])
                msg = last_entry.get("message", {})
                content = msg.get("content", [])

                if age < 4.0:
                    is_actively_writing = True
                    for c in content:
                        if isinstance(c, dict):
                            if c.get("type") == "tool_use":
                                tool_name = str(c.get("name", "tool"))
                                last_action = f"{tool_name}"
                            elif c.get("type") == "text":
                                txt = c.get("text", "").strip().split("\n")[0]
                                if txt:
                                    last_thought = txt[:50] + ("..." if len(txt) > 50 else "")
        except Exception:
            pass
    elif cmd_last_work_time == 0:
        cmd_last_work_time = now

    # Check for active non-idle child processes
    has_active_children = False
    for p in pids:
        try:
            children = subprocess.check_output(["pgrep", "-P", str(p)]).decode().strip().split()
            if children:
                has_active_children = True
        except Exception:
            pass

    is_active = is_actively_writing or has_active_children

    if is_active:
        cmd_was_working = True
        cmd_last_work_finish = now
        cmd_last_work_time = now
        short_action = last_action
        if len(short_action) > 30:
            short_action = short_action[:27] + "..."
        return {
            "open": True,
            "active": True,
            "state": "working",
            "action": short_action,
            "subtext": "Terminal Task",
            "message": last_thought or "Running command in terminal..."
        }
    else:
        # Check if recently finished working (success window ~4.5s)
        if cmd_was_working and (now - cmd_last_work_finish < 4.5):
            return {
                "open": True,
                "active": True,
                "state": "success",
                "action": "Task Complete",
                "subtext": "Success",
                "message": "Mission complete! Terminal task done."
            }
        else:
            cmd_was_working = False
            idle_duration = now - cmd_last_work_time
            if idle_duration > idle_timeout:
                return {
                    "open": False,
                    "active": False,
                    "state": "idle",
                    "action": "Standing by",
                    "subtext": "Offline (Idle)",
                    "message": "Standing by in terminal."
                }
            elif idle_duration > NAP_IDLE_SECONDS:
                return {
                    "open": True,
                    "active": False,
                    "state": "sleeping",
                    "action": "Taking a nap",
                    "subtext": "Titans Resting",
                    "message": "Taking a breather at Titans Tower. (Zzz...)"
                }
            else:
                return {
                    "open": True,
                    "active": False,
                    "state": "idle",
                    "action": "Standing by",
                    "subtext": "Terminal Ready",
                    "message": "Standing by in terminal. Ready for orders."
                }

def clean_thought_sentence(raw_text):
    if not raw_text:
        return ""
    text = re.sub(r'```.*?```', '', raw_text, flags=re.DOTALL)
    text = re.sub(r'[#*`_\[\]"]', '', text)
    lines = [l.strip() for l in text.split('\n') if l.strip() and not l.startswith('Thinking') and not l.startswith('Analysis') and not l.startswith('Let\'s check')]
    if lines:
        s = lines[0]
        if len(s) > 55:
            s = s[:52] + "..."
        return s
    return "Analyzing tactical parameters..."

agy_last_work_time = 0
agy_was_working = False
agy_completion_time = 0
last_handled_completed_step_idx = -1

def get_agy_status(transcript_path, idle_timeout=DEFAULT_IDLE_TIMEOUT):
    global agy_last_work_time, agy_was_working, agy_completion_time, last_handled_completed_step_idx
    now = time.time()
    
    is_running, _ = is_agy_running()
    
    # 🦇 If AGY is closed in terminal, immediately disappear
    if not is_running:
        agy_was_working = False
        agy_completion_time = 0
        return {
            "open": False,
            "active": False,
            "state": "idle",
            "action": "Standing by",
            "subtext": "Offline",
            "message": "Standing by in the Batcave."
        }

    if not transcript_path:
        if agy_last_work_time == 0:
            agy_last_work_time = now
        idle_duration = now - agy_last_work_time
        if idle_duration > idle_timeout:
            return {
                "open": False,
                "active": False,
                "state": "idle",
                "action": "Standing by",
                "subtext": "Offline (Idle)",
                "message": "Standing by in the Batcave."
            }
        elif idle_duration > NAP_IDLE_SECONDS:
            return {
                "open": True,
                "active": False,
                "state": "sleeping",
                "action": "Taking a nap",
                "subtext": "Batcave Resting",
                "message": "Resting between patrols in Gotham. (Zzz...)"
            }
        return {
            "open": True,
            "active": False,
            "state": "idle",
            "action": "Standing by",
            "subtext": "Batcave Ready",
            "message": "Batcave terminal online. Ready."
        }

    try:
        mtime = os.path.getmtime(transcript_path)
        age = now - mtime
        
        with open(transcript_path, "r", encoding="utf-8") as f:
            lines = [l.strip() for l in f if l.strip()]
        if not lines:
            last_step = {}
        else:
            last_step = json.loads(lines[-1])
            
        step_type = last_step.get("type", "")
        source = last_step.get("source", "")
        status = last_step.get("status", "")
        tool_calls = last_step.get("tool_calls", [])
        
        thought_msg = ""
        for l in reversed(lines[-10:]):
            st = json.loads(l)
            if st.get("thinking"):
                thought_msg = clean_thought_sentence(st.get("thinking"))
                break
        if not thought_msg:
            thought_msg = "Formulating tactical response..."

        # Scan the last 60 entries for latest PLANNER_RESPONSE and latest USER_INPUT
        latest_planner = None
        last_user_step_idx = -1
        latest_planner_step_idx = -1
        
        for l in reversed(lines[-60:]):
            st = json.loads(l)
            if latest_planner is None and st.get("type") == "PLANNER_RESPONSE":
                latest_planner = st
                latest_planner_step_idx = st.get("step_index", -1)
            if last_user_step_idx == -1 and st.get("type") == "USER_INPUT":
                last_user_step_idx = st.get("step_index", -1)
            if latest_planner is not None and last_user_step_idx != -1:
                break

        # Check if the query has completed (final model response with no tools and DONE status)
        is_final_response_done = (
            latest_planner is not None
            and (latest_planner.get("status") == "DONE")
            and (not latest_planner.get("tool_calls"))
            and (latest_planner_step_idx >= last_user_step_idx)
        )

        # 1. Freshly completed query (within 5 seconds of completion)
        if is_final_response_done and age < 5.0:
            return {
                "open": True,
                "active": True,
                "state": "success",
                "action": "Mission Complete",
                "subtext": "All Done",
                "message": "Mission accomplished! Query response completed."
            }

        # 2. Sleeping state: if idle for more than 5s (age >= 10.0s total, or age >= 5s after prompt completion)
        if age >= 10.0 or (is_final_response_done and age >= 5.0):
            if age > idle_timeout:
                return {
                    "open": False,
                    "active": False,
                    "state": "idle",
                    "action": "Standing by",
                    "subtext": "Offline (Idle)",
                    "message": "Standing by in the Batcave."
                }
            return {
                "open": True,
                "active": False,
                "state": "sleeping",
                "action": "Taking a nap",
                "subtext": "Batcave Resting",
                "message": "Resting between patrols in Gotham. (Zzz...)"
            }

        # 3. Standing by / Idle (5 seconds before taking a nap)
        if age >= 5.0:
            return {
                "open": True,
                "active": False,
                "state": "idle",
                "action": "Standing by",
                "subtext": "Batcave Ready",
                "message": "Watching over Gotham. Ready for commands."
            }

        # 4. If age < 5.0 and query is in progress, check active tool:
        active_tools = tool_calls or (latest_planner.get("tool_calls", []) if latest_planner else [])
        
        if active_tools:
            tc = active_tools[0]
            args = tc.get("args", {})
            if isinstance(args, str):
                try:
                    args = json.loads(args)
                except:
                    args = {}
            
            action = args.get("toolAction") or args.get("toolSummary") or "Executing tool"
            if isinstance(action, str) and action.startswith('"') and action.endswith('"'):
                action = action[1:-1]
            
            func_name = str(tc.get("name") or tc.get("function", {}).get("name", "tool"))
            
            short_action = action
            if len(short_action) > 30:
                short_action = short_action[:27] + "..."
            # 1. Waiting for agent and task (Separate 5th Animation)
            WAITING_TOOLS = {"invoke_subagent", "send_message", "manage_task", "manage_subagents", "schedule"}
            is_waiting = (func_name in WAITING_TOOLS) or any(k in action.lower() for k in ["wait", "await", "subagent", "schedule", "timer", "cron", "pending"])
            
            # 2. Edit and Execute CMD / Bash (Blue Animation Mode - SAME animation)
            TASK_TOOLS = {"write_to_file", "replace_file_content", "run_command", "generate_image"}
            is_task = (func_name in TASK_TOOLS) or any(k in action.lower() for k in ["edit", "write", "creat", "replac", "bash", "command", "execut", "run"])
            
            # 3. Read / Analysis / Generating (Yellow Mode)
            ANALYSIS_TOOLS = {"view_file", "list_dir", "grep_search", "find_by_name", "search_web", "read_url_content", "read_browser_page", "ask_question", "define_subagent"}
            is_analysis = (func_name in ANALYSIS_TOOLS) or any(k in action.lower() for k in ["read", "analyz", "view", "search", "grep", "find", "check", "inspect", "list", "clarif"])
            
            if is_waiting:
                return {
                    "open": True,
                    "active": True,
                    "state": "waiting",
                    "action": short_action,
                    "subtext": "Waiting",
                    "message": thought_msg or f"Awaiting completion of {func_name}..."
                }
            elif is_task:
                return {
                    "open": True,
                    "active": True,
                    "state": "working",
                    "action": short_action,
                    "subtext": "Doing Task",
                    "message": thought_msg or f"Executing {func_name}..."
                }
            else:
                return {
                    "open": True,
                    "active": True,
                    "state": "thinking",
                    "action": short_action,
                    "subtext": "Analysis",
                    "message": thought_msg or f"Analyzing {func_name} parameters..."
                }
        else:
            # Model is actively generating/thinking before tool calls
            return {
                "open": True,
                "active": True,
                "state": "thinking",
                "action": "Analyzing codebase",
                "subtext": "Analysis",
                "message": thought_msg or "Formulating tactical plan..."
            }
    except Exception:
        return {
            "open": is_running,
            "active": False,
            "state": "idle",
            "action": "Standing by",
            "subtext": "Idle",
            "message": "Standing by in the Batcave."
        }

def main():
    last_written = None
    while True:
        try:
            cfg = load_config()
            enabled = cfg.get("enabled", True)
            idle_timeout = float(cfg.get("idle_timeout", DEFAULT_IDLE_TIMEOUT))

            if not enabled:
                payload = {
                    "enabled": False,
                    "agy": {
                        "open": False,
                        "active": False,
                        "state": "idle",
                        "action": "Disabled",
                        "subtext": "Off",
                        "message": "Companion disabled."
                    },
                    "cmd": {
                        "open": False,
                        "active": False,
                        "state": "idle",
                        "action": "Disabled",
                        "subtext": "Off",
                        "message": "Companion disabled."
                    }
                }
            else:
                cmd_status = check_command_code_status(idle_timeout)
                latest_tr = find_latest_transcript()
                agy_status = get_agy_status(latest_tr, idle_timeout)
                
                payload = {
                    "enabled": True,
                    "agy": agy_status,
                    "cmd": cmd_status
                }
            
            raw = json.dumps(payload)
            if raw != last_written:
                with open(STATE_FILE + ".tmp", "w") as f:
                    f.write(raw)
                os.replace(STATE_FILE + ".tmp", STATE_FILE)
                last_written = raw
        except Exception:
            pass
        time.sleep(0.25)

if __name__ == "__main__":
    main()
