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
COMMANDCODE_DIR = os.path.expanduser("~/.commandcode")
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

def get_descendants(ppid):
    """
    Recursively find all non-trivial descendant processes of ppid.
    """
    descendants = []
    try:
        children = subprocess.check_output(["pgrep", "-P", str(ppid)]).decode().strip().split()
        for c in children:
            try:
                with open(f"/proc/{c}/cmdline", "rb") as f:
                    cmd = f.read().decode("utf-8", errors="ignore").replace("\0", " ").strip()
                if cmd and "daemon.py" not in cmd and cmd not in ["bash", "sh", "/bin/bash", "/bin/sh"]:
                    descendants.append({"pid": c, "cmd": cmd})
            except Exception:
                pass
            descendants.extend(get_descendants(c))
    except Exception:
        pass
    return descendants

def clean_thought_sentence(raw_text):
    if not raw_text:
        return ""
    text = re.sub(r'```.*?```', '', raw_text, flags=re.DOTALL)
    text = re.sub(r'[#*`_\[\]"]', '', text)
    lines = [l.strip() for l in text.split('\n') if l.strip() and not l.startswith('Thinking') and not l.startswith('Analysis') and not l.startswith("Let's check")]
    if lines:
        s = lines[0]
        if len(s) > 55:
            s = s[:52] + "..."
        return s
    return "Analyzing tactical parameters..."

# ==============================================================================
# 1. BATMAN (agy / Antigravity CLI)
# ==============================================================================

session_state_cache = {}

def get_running_agy_sessions():
    sessions = []
    try:
        pids = subprocess.check_output(["pgrep", "-f", r"(^|/)agy($|\s)"]).decode().strip().split()
    except Exception:
        return [], []

    valid_pids = []
    for pid in pids:
        try:
            with open(f"/proc/{pid}/cmdline", "rb") as f:
                cmd = f.read().decode("utf-8", errors="ignore").replace("\0", " ").strip()
            if not ("agy" in cmd) or "daemon.py" in cmd or "bot.py" in cmd:
                continue

            valid_pids.append(pid)
            fd_dir = f"/proc/{pid}/fd"
            if not os.path.exists(fd_dir):
                continue

            conv_ids = set()
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(os.path.join(fd_dir, fd))
                    m = re.search(r"/(?:conversations|presence)/([a-f0-9\-]{36})\.(?:db|lock)", target)
                    if m:
                        conv_ids.add(m.group(1))
                except Exception:
                    pass

            for cid in conv_ids:
                if not any(s["conv_id"] == cid for s in sessions):
                    sessions.append({
                        "pid": pid,
                        "conv_id": cid,
                        "descendants": get_descendants(pid)
                    })
        except Exception:
            pass

    if not sessions and valid_pids:
        try:
            jsonl_files = glob.glob(f"{GEMINI_BRAIN}/*/.system_generated/logs/transcript.jsonl")
            if jsonl_files:
                latest_tr = max(jsonl_files, key=os.path.getmtime)
                m = re.search(r"/brain/([a-f0-9\-]{36})/", latest_tr)
                if m:
                    sessions.append({
                        "pid": valid_pids[0],
                        "conv_id": m.group(1),
                        "descendants": get_descendants(valid_pids[0])
                    })
        except Exception:
            pass

    return sessions, valid_pids

def analyze_agy_session(sess, idle_timeout=DEFAULT_IDLE_TIMEOUT):
    conv_id = sess["conv_id"]
    pid = sess["pid"]
    descendants = sess.get("descendants", [])
    now = time.time()

    tr_path = os.path.join(GEMINI_BRAIN, conv_id, ".system_generated/logs/transcript.jsonl")
    if not os.path.exists(tr_path):
        return {
            "conv_id": conv_id,
            "open": True,
            "active": False,
            "state": "idle",
            "action": "Standing by",
            "subtext": "Batcave Ready",
            "message": "Standing by in the Batcave.",
            "mtime": 0,
            "priority": 1
        }

    mtime = os.path.getmtime(tr_path)
    age = now - mtime

    if conv_id not in session_state_cache:
        session_state_cache[conv_id] = {
            "last_completed_step_idx": -1,
            "completion_time": 0,
            "last_active_time": mtime if age > 10 else now
        }

    cache = session_state_cache[conv_id]

    try:
        with open(tr_path, "r", encoding="utf-8") as f:
            lines = [l.strip() for l in f if l.strip()]
    except Exception:
        lines = []

    latest_planner = None
    last_user_step_idx = -1
    latest_planner_step_idx = -1
    thought_msg = ""

    for l in reversed(lines[-100:]):
        try:
            st = json.loads(l)
            if latest_planner is None and st.get("type") == "PLANNER_RESPONSE":
                latest_planner = st
                latest_planner_step_idx = st.get("step_index", -1)
            if last_user_step_idx == -1 and st.get("type") == "USER_INPUT":
                last_user_step_idx = st.get("step_index", -1)
            if not thought_msg and st.get("thinking"):
                thought_msg = clean_thought_sentence(st.get("thinking"))
            if latest_planner is not None and last_user_step_idx != -1 and thought_msg:
                break
        except Exception:
            pass

    bg_tasks = []
    for d in descendants:
        cmd = d["cmd"]
        if any(x in cmd for x in ["gh auth", "login", "browser", "xdg-open", "task-"]):
            bg_tasks.append(cmd)
        elif not any(x in cmd for x in ["daemon.py", "ps ", "grep ", "pstree", "bash -c ps", "bash -c ls"]):
            bg_tasks.append(cmd)

    if last_user_step_idx == -1 and latest_planner is None:
        if age > NAP_IDLE_SECONDS:
            return {
                "conv_id": conv_id,
                "open": True,
                "active": False,
                "state": "sleeping",
                "action": "Taking a nap",
                "subtext": "Batcave Resting",
                "message": "Resting between patrols in Gotham. (Zzz...)",
                "mtime": mtime,
                "priority": 0
            }
        else:
            return {
                "conv_id": conv_id,
                "open": True,
                "active": False,
                "state": "idle",
                "action": "Standing by",
                "subtext": "Batcave Ready",
                "message": "Batcave terminal online. Ready.",
                "mtime": mtime,
                "priority": 1
            }

    is_query_done = (
        latest_planner is not None
        and (latest_planner.get("status") == "DONE")
        and (not latest_planner.get("tool_calls"))
        and (latest_planner_step_idx >= last_user_step_idx)
    )

    if is_query_done:
        if bg_tasks:
            cache["last_active_time"] = now
            cache["completion_time"] = 0
            task_name = bg_tasks[0]
            if len(task_name) > 30:
                task_name = task_name[:27] + "..."
            return {
                "conv_id": conv_id,
                "open": True,
                "active": True,
                "state": "waiting",
                "action": "Waiting for task",
                "subtext": "Waiting",
                "message": f"Awaiting background task: {task_name}",
                "mtime": mtime,
                "priority": 4
            }

        if latest_planner_step_idx != cache["last_completed_step_idx"]:
            cache["last_completed_step_idx"] = latest_planner_step_idx
            if age < 8.0:
                cache["completion_time"] = now
                cache["last_active_time"] = now
            else:
                cache["completion_time"] = 0
                cache["last_active_time"] = mtime

        if cache["completion_time"] > 0 and (now - cache["completion_time"] < 8.0):
            return {
                "conv_id": conv_id,
                "open": True,
                "active": True,
                "state": "success",
                "action": "Mission Complete",
                "subtext": "All Done",
                "message": "Mission accomplished! Query response completed.",
                "mtime": mtime,
                "priority": 2
            }
        else:
            idle_duration = now - max(cache["completion_time"] + 8.0 if cache["completion_time"] > 0 else 0, cache["last_active_time"])
            if idle_duration > idle_timeout:
                return {
                    "conv_id": conv_id,
                    "open": False,
                    "active": False,
                    "state": "idle",
                    "action": "Standing by",
                    "subtext": "Offline (Idle)",
                    "message": "Standing by in the Batcave.",
                    "mtime": mtime,
                    "priority": 0
                }
            elif idle_duration > NAP_IDLE_SECONDS:
                return {
                    "conv_id": conv_id,
                    "open": True,
                    "active": False,
                    "state": "sleeping",
                    "action": "Taking a nap",
                    "subtext": "Batcave Resting",
                    "message": "Resting between patrols in Gotham. (Zzz...)",
                    "mtime": mtime,
                    "priority": 0
                }
            else:
                return {
                    "conv_id": conv_id,
                    "open": True,
                    "active": False,
                    "state": "idle",
                    "action": "Standing by",
                    "subtext": "Batcave Ready",
                    "message": "Watching over Gotham. Ready for commands.",
                    "mtime": mtime,
                    "priority": 1
                }

    cache["last_active_time"] = now
    cache["completion_time"] = 0

    if age > 15.0 and not bg_tasks:
        idle_duration = age - 15.0
        if idle_duration > NAP_IDLE_SECONDS:
            return {
                "conv_id": conv_id,
                "open": True,
                "active": False,
                "state": "sleeping",
                "action": "Taking a nap",
                "subtext": "Batcave Resting",
                "message": "Resting between patrols in Gotham. (Zzz...)",
                "mtime": mtime,
                "priority": 0
            }
        return {
            "conv_id": conv_id,
            "open": True,
            "active": False,
            "state": "idle",
            "action": "Standing by",
            "subtext": "Batcave Ready",
            "message": "Watching over Gotham. Ready for commands.",
            "mtime": mtime,
            "priority": 1
        }

    active_tools = (latest_planner.get("tool_calls", []) if latest_planner else [])
    if active_tools:
        tc = active_tools[0]
        args = tc.get("args", {})
        if isinstance(args, str):
            try: args = json.loads(args)
            except Exception: args = {}
        action = args.get("toolAction") or args.get("toolSummary") or "Executing tool"
        if isinstance(action, str) and action.startswith('"') and action.endswith('"'):
            action = action[1:-1]
        func_name = str(tc.get("name") or tc.get("function", {}).get("name", "tool"))
        short_action = action[:27] + "..." if len(action) > 30 else action

        WAITING_TOOLS = {"invoke_subagent", "send_message", "manage_task", "manage_subagents", "schedule", "ask_question"}
        is_waiting = (func_name in WAITING_TOOLS) or any(k in action.lower() for k in ["wait", "await", "subagent", "schedule", "timer", "cron", "pending", "question"])

        TASK_TOOLS = {"write_to_file", "replace_file_content", "run_command", "generate_image"}
        is_task = (func_name in TASK_TOOLS) or any(k in action.lower() for k in ["edit", "write", "creat", "replac", "bash", "command", "execut", "run"])

        if is_waiting:
            return {
                "conv_id": conv_id,
                "open": True,
                "active": True,
                "state": "waiting",
                "action": short_action,
                "subtext": "Waiting",
                "message": thought_msg or f"Awaiting completion of {func_name}...",
                "mtime": mtime,
                "priority": 4
            }
        elif is_task:
            return {
                "conv_id": conv_id,
                "open": True,
                "active": True,
                "state": "working",
                "action": short_action,
                "subtext": "Doing Task",
                "message": thought_msg or f"Executing {func_name}...",
                "mtime": mtime,
                "priority": 5
            }
        else:
            return {
                "conv_id": conv_id,
                "open": True,
                "active": True,
                "state": "thinking",
                "action": short_action,
                "subtext": "Analysis",
                "message": thought_msg or f"Analyzing {func_name} parameters...",
                "mtime": mtime,
                "priority": 3
            }

    return {
        "conv_id": conv_id,
        "open": True,
        "active": True,
        "state": "thinking",
        "action": "Analyzing codebase",
        "subtext": "Analysis",
        "message": thought_msg or "Formulating tactical plan...",
        "mtime": mtime,
        "priority": 3
    }

def get_agy_status(idle_timeout=DEFAULT_IDLE_TIMEOUT):
    sessions, valid_pids = get_running_agy_sessions()
    if not valid_pids:
        return {
            "open": False,
            "active": False,
            "state": "idle",
            "action": "Standing by",
            "subtext": "Offline",
            "message": "Standing by in the Batcave."
        }

    if not sessions:
        return {
            "open": True,
            "active": False,
            "state": "idle",
            "action": "Standing by",
            "subtext": "Batcave Ready",
            "message": "Batcave terminal online. Ready."
        }

    evaluated = [analyze_agy_session(s, idle_timeout) for s in sessions]
    evaluated.sort(key=lambda x: (x.get("priority", 0), x.get("mtime", 0)), reverse=True)
    best = evaluated[0]

    return {
        "open": best["open"],
        "active": best["active"],
        "state": best["state"],
        "action": best["action"],
        "subtext": best["subtext"],
        "message": best["message"]
    }

# ==============================================================================
# 2. ROBIN (cmd / Command Code)
# ==============================================================================

cmd_session_cache = {}

def get_running_cmd_sessions():
    pids = []
    try:
        raw = subprocess.check_output(["pgrep", "-f", r"(command-code|bin/cmd|(^|/)cmd($|\s))"]).decode().strip().split()
        for p in raw:
            try:
                with open(f"/proc/{p}/cmdline", "rb") as f:
                    cmd = f.read().decode("utf-8", errors="ignore").replace("\0", " ").strip()
                if any(x in cmd for x in ["bin/cmd", "command-code", "/cmd "]) and "daemon.py" not in cmd and "grep" not in cmd:
                    pids.append(p)
            except Exception:
                pass
    except Exception:
        pass

    sessions = []
    for p in pids:
        # Get cwd to match project
        cwd = None
        try:
            cwd = os.readlink(f"/proc/{p}/cwd")
        except Exception:
            pass

        # Find matching session file
        session_file = None
        if cwd:
            slug = cwd.strip("/").replace("/", "-")
            proj_pattern = os.path.join(COMMANDCODE_DIR, "projects", f"*{slug}*", "*.jsonl")
            proj_files = [f for f in glob.glob(proj_pattern) if not f.endswith(".checkpoints.jsonl")]
            if proj_files:
                session_file = max(proj_files, key=os.path.getmtime)

        if not session_file:
            all_files = [f for f in glob.glob(os.path.join(COMMANDCODE_DIR, "projects", "*", "*.jsonl")) if not f.endswith(".checkpoints.jsonl")]
            if all_files:
                session_file = max(all_files, key=os.path.getmtime)

        sessions.append({
            "pid": p,
            "cwd": cwd,
            "session_file": session_file,
            "descendants": get_descendants(p)
        })

    return sessions, pids

def analyze_cmd_session(sess, idle_timeout=DEFAULT_IDLE_TIMEOUT):
    pid = sess["pid"]
    session_file = sess.get("session_file")
    descendants = sess.get("descendants", [])
    now = time.time()

    if not session_file or not os.path.exists(session_file):
        return {
            "open": True,
            "active": False,
            "state": "idle",
            "action": "Standing by",
            "subtext": "Terminal Ready",
            "message": "Standing by in terminal. Ready for orders.",
            "mtime": 0,
            "priority": 1
        }

    mtime = os.path.getmtime(session_file)
    age = now - mtime
    session_key = session_file

    if session_key not in cmd_session_cache:
        cmd_session_cache[session_key] = {
            "last_completed_msg_id": None,
            "completion_time": 0,
            "last_active_time": mtime if age > 10 else now
        }

    cache = cmd_session_cache[session_key]

    try:
        with open(session_file, "r", encoding="utf-8") as f:
            lines = [l.strip() for l in f if l.strip()]
    except Exception:
        lines = []

    # Check child processes actively running
    bg_tasks = []
    for d in descendants:
        cmd = d["cmd"]
        if not any(x in cmd for x in ["daemon.py", "ps ", "grep ", "pstree", "bash -c ps", "bash -c ls"]):
            bg_tasks.append(cmd)

    if bg_tasks:
        cache["last_active_time"] = now
        cache["completion_time"] = 0
        task_name = bg_tasks[0]
        # Clean task name for action
        t_clean = os.path.basename(task_name.split()[0])
        action_name = f"Running {t_clean}"
        if len(action_name) > 30:
            action_name = action_name[:27] + "..."
        msg_preview = task_name[:50] + ("..." if len(task_name) > 50 else "")
        return {
            "open": True,
            "active": True,
            "state": "working",
            "action": action_name,
            "subtext": "Doing Task",
            "message": f"Executing: {msg_preview}",
            "mtime": now,
            "priority": 5
        }

    if not lines:
        if age > NAP_IDLE_SECONDS:
            return {
                "open": True,
                "active": False,
                "state": "sleeping",
                "action": "Taking a nap",
                "subtext": "Titans Resting",
                "message": "Taking a breather at Titans Tower. (Zzz...)",
                "mtime": mtime,
                "priority": 0
            }
        return {
            "open": True,
            "active": False,
            "state": "idle",
            "action": "Standing by",
            "subtext": "Terminal Ready",
            "message": "Standing by in terminal. Ready for orders.",
            "mtime": mtime,
            "priority": 1
        }

    # Find the latest messages
    last_assistant_entry = None
    last_user_entry = None
    last_entry = None
    thought_msg = ""

    for l in reversed(lines[-50:]):
        try:
            entry = json.loads(l)
            if last_entry is None:
                last_entry = entry
            msg = entry.get("message", {})
            role = msg.get("role")
            if last_assistant_entry is None and role == "assistant":
                last_assistant_entry = entry
            if last_user_entry is None and role == "user":
                last_user_entry = entry
            if not thought_msg:
                for c in msg.get("content", []):
                    if isinstance(c, dict):
                        if c.get("type") == "thinking" and c.get("thinking"):
                            thought_msg = clean_thought_sentence(c.get("thinking"))
                        elif c.get("type") == "text" and role == "assistant":
                            txt = c.get("text", "").strip()
                            if txt.startswith("I'm ") or txt.startswith("I will ") or txt.startswith("Let's ") or txt.startswith("Analyzing"):
                                thought_msg = clean_thought_sentence(txt)
            if last_assistant_entry and last_user_entry and thought_msg:
                break
        except Exception:
            pass

    last_entry_msg = (last_entry.get("message", {}) if last_entry else {})
    last_role = last_entry_msg.get("role")
    last_content = last_entry_msg.get("content", [])

    # Check for active tool calls in last assistant message
    active_tools = []
    if last_assistant_entry:
        asst_content = last_assistant_entry.get("message", {}).get("content", [])
        for c in asst_content:
            if isinstance(c, dict) and c.get("type") == "tool_use":
                active_tools.append(c)

    # Has tool results returned?
    has_unreturned_tools = False
    if active_tools and last_role == "assistant":
        has_unreturned_tools = True

    # 1. Check if Assistant is actively working or analyzing tools
    if has_unreturned_tools and age < 60.0:
        tc = active_tools[-1]
        tool_name = str(tc.get("name", "tool"))
        tool_input = tc.get("input", {})
        if isinstance(tool_input, str):
            try: tool_input = json.loads(tool_input)
            except Exception: tool_input = {}

        # Categorize tools
        TASK_TOOLS = {"edit_file", "write_file", "create_file", "replace_file_content", "patch_file", "shell_command", "bash", "run_command", "execute_command", "todo_write", "save_file", "apply_diff"}
        WAITING_TOOLS = {"ask_question", "confirm", "prompt", "user_input", "wait_task", "request_feedback"}
        ANALYSIS_TOOLS = {"read_file", "view_file", "grep", "find", "list_dir", "web_search", "fetch_web_page", "search_code", "codebase_search", "directory_list"}

        is_task = (tool_name in TASK_TOOLS)
        is_waiting = (tool_name in WAITING_TOOLS)
        is_analysis = (tool_name in ANALYSIS_TOOLS)

        # Generate readable action text
        if tool_name in ["edit_file", "write_file", "create_file", "patch_file"]:
            fp = tool_input.get("file_path", "")
            action_text = f"Editing {os.path.basename(fp)}" if fp else "Editing file"
        elif tool_name == "shell_command":
            desc = tool_input.get("description") or tool_input.get("command", "")
            action_text = desc.split("\n")[0][:25] if desc else "Running shell command"
        elif tool_name == "todo_write":
            action_text = "Updating task plan"
        elif tool_name in ["read_file", "view_file"]:
            fp = tool_input.get("file_path", "")
            action_text = f"Reading {os.path.basename(fp)}" if fp else "Reading file"
        elif tool_name in ["grep", "find", "search_code"]:
            pat = tool_input.get("pattern") or tool_input.get("query") or "code"
            action_text = f"Searching '{pat}'"
        elif tool_name == "web_search":
            q = tool_input.get("query", "web")
            action_text = f"Searching {q[:20]}"
        else:
            action_text = f"{tool_name}"

        if len(action_text) > 30:
            action_text = action_text[:27] + "..."

        cache["last_active_time"] = now
        cache["completion_time"] = 0

        if is_waiting:
            return {
                "open": True,
                "active": True,
                "state": "waiting",
                "action": action_text,
                "subtext": "Waiting",
                "message": thought_msg or "Awaiting confirmation / option in terminal...",
                "mtime": mtime,
                "priority": 4
            }
        elif is_task:
            return {
                "open": True,
                "active": True,
                "state": "working",
                "action": action_text,
                "subtext": "Doing Task",
                "message": thought_msg or f"Executing {tool_name} in workspace...",
                "mtime": mtime,
                "priority": 5
            }
        else:
            return {
                "open": True,
                "active": True,
                "state": "thinking",
                "action": action_text,
                "subtext": "Analysis",
                "message": thought_msg or f"Analyzing parameters with {tool_name}...",
                "mtime": mtime,
                "priority": 3
            }

    # 2. Check if newly submitted User prompt is actively being analyzed (age < 5s)
    if last_role == "user" and age < 6.0:
        cache["last_active_time"] = now
        cache["completion_time"] = 0
        return {
            "open": True,
            "active": True,
            "state": "thinking",
            "action": "Analyzing plan",
            "subtext": "Planning",
            "message": thought_msg or "Formulating tactical plan for task...",
            "mtime": mtime,
            "priority": 3
        }

    # 3. Check for waiting confirmation prompts in the assistant output
    if last_role == "assistant":
        last_txt = ""
        for c in last_content:
            if isinstance(c, dict) and c.get("type") == "text":
                last_txt = c.get("text", "").strip()

        # Check if assistant is asking a question / confirmation
        is_asking = any(k in last_txt.lower() for k in ["[y/n]", "continue", "choice", "switch to model", "confirm", "proceed?"])
        if is_asking and age < 180.0:
            cache["last_active_time"] = now
            cache["completion_time"] = 0
            return {
                "open": True,
                "active": True,
                "state": "waiting",
                "action": "Waiting for option",
                "subtext": "Waiting",
                "message": thought_msg or "Awaiting your selection / confirmation in terminal...",
                "mtime": mtime,
                "priority": 4
            }

    # 4. Turn Complete / Success Celebration
    msg_id = (last_entry.get("id") if last_entry else str(len(lines)))
    if msg_id != cache["last_completed_msg_id"]:
        cache["last_completed_msg_id"] = msg_id
        if age < 8.0:
            cache["completion_time"] = now
            cache["last_active_time"] = now
        else:
            cache["completion_time"] = 0
            cache["last_active_time"] = mtime

    if cache["completion_time"] > 0 and (now - cache["completion_time"] < 8.0):
        return {
            "open": True,
            "active": True,
            "state": "success",
            "action": "Task Complete",
            "subtext": "Success",
            "message": "Mission complete! Terminal task accomplished.",
            "mtime": mtime,
            "priority": 2
        }

    # 5. Idle / Sleep Transition
    idle_duration = now - max(cache["completion_time"] + 8.0 if cache["completion_time"] > 0 else 0, cache["last_active_time"])
    if idle_duration > idle_timeout:
        return {
            "open": False,
            "active": False,
            "state": "idle",
            "action": "Standing by",
            "subtext": "Offline (Idle)",
            "message": "Standing by in terminal.",
            "mtime": mtime,
            "priority": 0
        }
    elif idle_duration > NAP_IDLE_SECONDS:
        return {
            "open": True,
            "active": False,
            "state": "sleeping",
            "action": "Taking a nap",
            "subtext": "Titans Resting",
            "message": "Taking a breather at Titans Tower. (Zzz...)",
            "mtime": mtime,
            "priority": 0
        }
    else:
        return {
            "open": True,
            "active": False,
            "state": "idle",
            "action": "Standing by",
            "subtext": "Terminal Ready",
            "message": "Standing by in terminal. Ready for orders.",
            "mtime": mtime,
            "priority": 1
        }

def check_command_code_status(idle_timeout=DEFAULT_IDLE_TIMEOUT):
    sessions, valid_pids = get_running_cmd_sessions()
    if not valid_pids:
        return {
            "open": False,
            "active": False,
            "state": "idle",
            "action": "Standing by",
            "subtext": "Offline",
            "message": "Standing by in terminal."
        }

    if not sessions:
        return {
            "open": True,
            "active": False,
            "state": "idle",
            "action": "Standing by",
            "subtext": "Terminal Ready",
            "message": "Standing by in terminal. Ready for orders."
        }

    evaluated = [analyze_cmd_session(s, idle_timeout) for s in sessions]
    evaluated.sort(key=lambda x: (x.get("priority", 0), x.get("mtime", 0)), reverse=True)
    best = evaluated[0]

    return {
        "open": best["open"],
        "active": best["active"],
        "state": best["state"],
        "action": best["action"],
        "subtext": best["subtext"],
        "message": best["message"]
    }

# ==============================================================================
# MAIN EVENT LOOP
# ==============================================================================

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
                    "agy": {"open": False, "active": False, "state": "idle", "action": "Disabled", "subtext": "Off", "message": "Disabled."},
                    "cmd": {"open": False, "active": False, "state": "idle", "action": "Disabled", "subtext": "Off", "message": "Disabled."}
                }
            else:
                agy_status = get_agy_status(idle_timeout)
                cmd_status = check_command_code_status(idle_timeout)

                payload = {
                    "enabled": True,
                    "agy": agy_status,
                    "cmd": cmd_status
                }

            raw = json.dumps(payload)
            if raw != last_written:
                with open(STATE_FILE, "w") as f:
                    f.write(raw)
                last_written = raw
        except Exception:
            pass
        time.sleep(0.08)

if __name__ == "__main__":
    main()
