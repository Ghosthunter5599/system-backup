#include <iostream>
#include <fstream>
#include <sstream>
#include <string>
#include <vector>
#include <map>
#include <set>
#include <chrono>
#include <filesystem>
#include <algorithm>
#include <thread>
#include <unistd.h>
#include <limits.h>
#include <signal.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <dirent.h>
#include <json/json.h>

namespace fs = std::filesystem;

static const std::string STATE_FILE = "/tmp/agent-companion-state.json";
static const double NAP_IDLE_SECONDS = 5.0;
static const double DEFAULT_IDLE_TIMEOUT = 1800.0;

std::string get_home_dir() {
    const char* h = getenv("HOME");
    return h ? std::string(h) : "/home/b47m4n";
}

std::string clean_thought_sentence(const std::string& raw_text) {
    if (raw_text.empty()) return "Analyzing tactical parameters...";
    std::string s = raw_text;
    
    // Remove markdown code blocks and backticks
    size_t pos = 0;
    while ((pos = s.find("```")) != std::string::npos) {
        size_t end = s.find("```", pos + 3);
        if (end == std::string::npos) break;
        s.erase(pos, end - pos + 3);
    }
    
    // Remove special chars
    std::string clean;
    for (char c : s) {
        if (c != '#' && c != '*' && c != '`' && c != '_' && c != '[' && c != ']' && c != '"' && c != '\n' && c != '\r') {
            clean += c;
        } else if (c == '\n' || c == '\r') {
            clean += ' ';
        }
    }
    
    // Trim and normalize whitespace
    std::string trimmed;
    bool in_space = false;
    for (char c : clean) {
        if (c == ' ' || c == '\t') {
            if (!in_space && !trimmed.empty()) {
                trimmed += ' ';
                in_space = true;
            }
        } else {
            trimmed += c;
            in_space = false;
        }
    }
    
    if (trimmed.empty()) return "Analyzing tactical parameters...";
    if (trimmed.length() > 55) {
        trimmed = trimmed.substr(0, 52) + "...";
    }
    return trimmed;
}

std::vector<std::string> read_last_lines(const std::string& filepath, int max_lines) {
    std::vector<std::string> lines;
    std::ifstream file(filepath);
    if (!file.is_open()) return lines;
    
    std::string line;
    while (std::getline(file, line)) {
        if (!line.empty()) {
            lines.push_back(line);
            if ((int)lines.size() > max_lines * 3) {
                lines.erase(lines.begin(), lines.begin() + max_lines);
            }
        }
    }
    if ((int)lines.size() > max_lines) {
        lines.erase(lines.begin(), lines.end() - max_lines);
    }
    return lines;
}

double get_file_mtime(const std::string& path) {
    struct stat st;
    if (stat(path.c_str(), &st) == 0) {
        return (double)st.st_mtim.tv_sec + (double)st.st_mtim.tv_nsec / 1e9;
    }
    return 0.0;
}

double now_sec() {
    using namespace std::chrono;
    return duration_cast<duration<double>>(system_clock::now().time_since_epoch()).count();
}

std::string get_process_cwd(int pid) {
    char buf[PATH_MAX];
    std::string link = "/proc/" + std::to_string(pid) + "/cwd";
    ssize_t len = readlink(link.c_str(), buf, sizeof(buf) - 1);
    if (len != -1) {
        buf[len] = '\0';
        return std::string(buf);
    }
    return "";
}

struct AgentState {
    bool open = false;
    bool active = false;
    std::string state = "idle";
    std::string action = "Standing by";
    std::string subtext = "Ready";
    std::string message = "Standing by.";
    double mtime = 0.0;
    int priority = 0;
};

// Process cache to eliminate /proc overhead
struct PidCache {
    std::vector<int> pids;
    double last_scan_time = 0.0;
};

static std::map<std::string, PidCache> g_pid_caches;

std::vector<int> get_cached_pids(const std::string& pattern) {
    double now = now_sec();
    auto& entry = g_pid_caches[pattern];
    
    // Check if cached PIDs are still alive
    if (!entry.pids.empty()) {
        std::vector<int> alive;
        for (int p : entry.pids) {
            if (kill(p, 0) == 0) alive.push_back(p);
        }
        entry.pids = alive;
        if (!entry.pids.empty() && (now - entry.last_scan_time < 2.0)) {
            return entry.pids;
        }
    }
    
    if (now - entry.last_scan_time < 1.5 && entry.pids.empty()) {
        return entry.pids;
    }
    
    entry.last_scan_time = now;
    entry.pids.clear();
    
    DIR* dir = opendir("/proc");
    if (!dir) return entry.pids;
    
    struct dirent* dent;
    while ((dent = readdir(dir)) != nullptr) {
        if (dent->d_type == DT_DIR) {
            char* endptr = nullptr;
            long pid = strtol(dent->d_name, &endptr, 10);
            if (*endptr == '\0') {
                std::string cmdline_path = "/proc/" + std::string(dent->d_name) + "/cmdline";
                std::ifstream f(cmdline_path, std::ios::binary);
                if (f.is_open()) {
                    std::string cmd((std::istreambuf_iterator<char>(f)), std::istreambuf_iterator<char>());
                    std::replace(cmd.begin(), cmd.end(), '\0', ' ');
                    if (cmd.find(pattern) != std::string::npos && 
                        cmd.find("companion-daemon") == std::string::npos && 
                        cmd.find("daemon.py") == std::string::npos && 
                        cmd.find("grep") == std::string::npos) {
                        entry.pids.push_back((int)pid);
                    }
                }
            }
        }
    }
    closedir(dir);
    return entry.pids;
}

// ==============================================================================
// 1. BATMAN (agy / Antigravity CLI)
// ==============================================================================

struct AgyParsedInfo {
    int last_user_step_idx = -1;
    int latest_planner_step_idx = -1;
    std::string latest_planner_status;
    std::string thought_msg;
    std::string tool_func_name;
    std::string tool_action_name;
    bool is_query_done = false;
};

struct AgySessionCache {
    double last_parsed_mtime = 0.0;
    AgyParsedInfo info;
    int last_completed_step_idx = -1;
    double completion_time = 0.0;
    double last_active_time = 0.0;
};

static std::map<std::string, AgySessionCache> agy_cache;
static std::vector<std::pair<std::string, double>> g_cached_agy_sessions;
static double g_last_agy_scan_time = 0.0;

AgentState analyze_agy_session(int pid, const std::string& conv_id, double idle_timeout) {
    AgentState res;
    res.open = true;
    res.active = false;
    res.state = "idle";
    res.action = "Standing by";
    res.subtext = "Batcave Ready";
    res.message = "Standing by in the Batcave.";
    res.priority = 1;
    
    std::string brain_dir = get_home_dir() + "/.gemini/antigravity-cli/brain/" + conv_id;
    std::string tr_path = brain_dir + "/.system_generated/logs/transcript.jsonl";
    if (!fs::exists(tr_path)) return res;
    
    double mtime = get_file_mtime(tr_path);
    double now = now_sec();
    double age = now - mtime;
    res.mtime = mtime;
    
    if (agy_cache.find(conv_id) == agy_cache.end()) {
        agy_cache[conv_id] = AgySessionCache();
        agy_cache[conv_id].last_active_time = (age > 10.0 ? mtime : now);
    }
    auto& cache = agy_cache[conv_id];
    
    // Only re-parse file when mtime changed
    if (mtime != cache.last_parsed_mtime) {
        cache.last_parsed_mtime = mtime;
        cache.info = AgyParsedInfo();
        
        auto lines = read_last_lines(tr_path, 80);
        Json::CharReaderBuilder reader_builder;
        
        for (auto it = lines.rbegin(); it != lines.rend(); ++it) {
            Json::Value root;
            std::string errs;
            std::istringstream iss(*it);
            if (Json::parseFromStream(reader_builder, iss, &root, &errs)) {
                std::string type = root.get("type", "").asString();
                int step_idx = root.get("step_index", -1).asInt();
                if (cache.info.latest_planner_step_idx == -1 && type == "PLANNER_RESPONSE") {
                    cache.info.latest_planner_step_idx = step_idx;
                    cache.info.latest_planner_status = root.get("status", "").asString();
                    auto tool_calls = root.get("tool_calls", Json::arrayValue);
                    if (!tool_calls.empty()) {
                        auto tc = tool_calls[0];
                        cache.info.tool_func_name = tc.isMember("name") ? tc["name"].asString() : "";
                        if (tc.isMember("args")) {
                            auto args = tc["args"];
                            if (args.isString()) {
                                Json::Value parsed_args;
                                std::string perrs;
                                std::istringstream piss(args.asString());
                                if (Json::parseFromStream(reader_builder, piss, &parsed_args, &perrs)) {
                                    args = parsed_args;
                                }
                            }
                            if (args.isMember("toolAction")) cache.info.tool_action_name = args["toolAction"].asString();
                            else if (args.isMember("toolSummary")) cache.info.tool_action_name = args["toolSummary"].asString();
                        }
                    }
                }
                if (cache.info.last_user_step_idx == -1 && type == "USER_INPUT") {
                    cache.info.last_user_step_idx = step_idx;
                }
                if (cache.info.thought_msg.empty() && root.isMember("thinking")) {
                    cache.info.thought_msg = clean_thought_sentence(root["thinking"].asString());
                }
                if (cache.info.latest_planner_step_idx != -1 && cache.info.last_user_step_idx != -1 && !cache.info.thought_msg.empty()) {
                    break;
                }
            }
        }
        
        cache.info.is_query_done = (cache.info.latest_planner_step_idx != -1 && 
                                   cache.info.latest_planner_status == "DONE" && 
                                   cache.info.tool_func_name.empty() && 
                                   cache.info.latest_planner_step_idx >= cache.info.last_user_step_idx);
    }
    
    if (cache.info.last_user_step_idx == -1 && cache.info.latest_planner_step_idx == -1) {
        if (age > NAP_IDLE_SECONDS) {
            res.state = "sleeping";
            res.action = "Taking a nap";
            res.subtext = "Batcave Resting";
            res.message = "Resting between patrols in Gotham. (Zzz...)";
            res.priority = 0;
        }
        return res;
    }
    
    if (cache.info.is_query_done) {
        if (cache.info.latest_planner_step_idx != cache.last_completed_step_idx) {
            cache.last_completed_step_idx = cache.info.latest_planner_step_idx;
            if (age < 8.0) {
                cache.completion_time = now;
                cache.last_active_time = now;
            } else {
                cache.completion_time = 0.0;
                cache.last_active_time = mtime;
            }
        }
        
        if (cache.completion_time > 0.0 && (now - cache.completion_time < 8.0)) {
            res.active = true;
            res.state = "success";
            res.action = "Mission Complete";
            res.subtext = "All Done";
            res.message = "Mission accomplished! Query response completed.";
            res.priority = 2;
            return res;
        } else {
            double idle_dur = now - std::max(cache.completion_time > 0.0 ? cache.completion_time + 8.0 : 0.0, cache.last_active_time);
            if (idle_dur > idle_timeout) {
                res.open = false;
                res.state = "idle";
                res.subtext = "Offline (Idle)";
                res.priority = 0;
            } else if (idle_dur > NAP_IDLE_SECONDS) {
                res.state = "sleeping";
                res.action = "Taking a nap";
                res.subtext = "Batcave Resting";
                res.message = "Resting between patrols in Gotham. (Zzz...)";
                res.priority = 0;
            } else {
                res.state = "idle";
                res.action = "Standing by";
                res.subtext = "Batcave Ready";
                res.message = "Watching over Gotham. Ready for commands.";
                res.priority = 1;
            }
            return res;
        }
    }
    
    cache.last_active_time = now;
    cache.completion_time = 0.0;
    
    if (age > 25.0) {
        double idle_dur = age - 25.0;
        if (idle_dur > NAP_IDLE_SECONDS) {
            res.state = "sleeping";
            res.action = "Taking a nap";
            res.subtext = "Batcave Resting";
            res.message = "Resting between patrols in Gotham. (Zzz...)";
            res.priority = 0;
        }
        return res;
    }
    
    if (!cache.info.tool_func_name.empty()) {
        std::string func_name = cache.info.tool_func_name;
        std::string action = cache.info.tool_action_name.empty() ? func_name : cache.info.tool_action_name;
        std::string short_action = action.length() > 30 ? action.substr(0, 27) + "..." : action;
        
        static const std::set<std::string> WAITING_TOOLS = {"invoke_subagent", "send_message", "manage_task", "manage_subagents", "schedule", "ask_question"};
        static const std::set<std::string> TASK_TOOLS = {"write_to_file", "replace_file_content", "run_command", "generate_image"};
        
        if (WAITING_TOOLS.count(func_name) || action.find("wait") != std::string::npos || action.find("question") != std::string::npos) {
            res.active = true;
            res.state = "waiting";
            res.action = short_action;
            res.subtext = "Waiting";
            res.message = cache.info.thought_msg.empty() ? "Awaiting completion of " + func_name + "..." : cache.info.thought_msg;
            res.priority = 4;
            return res;
        } else if (TASK_TOOLS.count(func_name) || action.find("edit") != std::string::npos || action.find("write") != std::string::npos || action.find("execut") != std::string::npos) {
            res.active = true;
            res.state = "working";
            res.action = short_action;
            res.subtext = "Doing Task";
            res.message = cache.info.thought_msg.empty() ? "Executing " + func_name + "..." : cache.info.thought_msg;
            res.priority = 5;
            return res;
        } else {
            res.active = true;
            res.state = "thinking";
            res.action = short_action;
            res.subtext = "Analysis";
            res.message = cache.info.thought_msg.empty() ? "Analyzing " + func_name + " parameters..." : cache.info.thought_msg;
            res.priority = 3;
            return res;
        }
    }
    
    res.active = true;
    res.state = "thinking";
    res.action = "Analyzing codebase";
    res.subtext = "Analysis";
    res.message = cache.info.thought_msg.empty() ? "Formulating tactical plan..." : cache.info.thought_msg;
    res.priority = 3;
    return res;
}

AgentState get_agy_status(double idle_timeout) {
    auto pids = get_cached_pids("agy");
    if (pids.empty()) {
        AgentState s;
        s.open = false;
        s.active = false;
        s.state = "idle";
        s.action = "Standing by";
        s.subtext = "Offline";
        s.message = "Standing by in the Batcave.";
        return s;
    }
    
    double now = now_sec();
    if (now - g_last_agy_scan_time > 1.5 || g_cached_agy_sessions.empty()) {
        g_last_agy_scan_time = now;
        g_cached_agy_sessions.clear();
        std::string brain_base = get_home_dir() + "/.gemini/antigravity-cli/brain";
        if (fs::exists(brain_base)) {
            for (const auto& entry : fs::directory_iterator(brain_base)) {
                if (entry.is_directory()) {
                    std::string tr = entry.path().string() + "/.system_generated/logs/transcript.jsonl";
                    if (fs::exists(tr)) {
                        g_cached_agy_sessions.push_back({entry.path().filename().string(), get_file_mtime(tr)});
                    }
                }
            }
        }
        std::sort(g_cached_agy_sessions.begin(), g_cached_agy_sessions.end(), [](const auto& a, const auto& b) {
            return a.second > b.second;
        });
    }
    
    if (g_cached_agy_sessions.empty()) {
        AgentState s;
        s.open = true;
        s.active = false;
        s.state = "idle";
        s.action = "Standing by";
        s.subtext = "Batcave Ready";
        s.message = "Batcave terminal online. Ready.";
        return s;
    }
    
    return analyze_agy_session(pids[0], g_cached_agy_sessions[0].first, idle_timeout);
}

// ==============================================================================
// 2. ROBIN (cmd / Command Code)
// ==============================================================================

struct CmdParsedInfo {
    std::string last_entry_id;
    std::string last_role;
    bool last_is_tool_result = false;
    bool has_pending_tools = false;
    std::string pending_tool_name;
    std::string pending_tool_file;
    std::string pending_tool_action;
    bool pending_is_plan = false;
    bool assistant_asking_option = false;
    std::string thought_msg;
};

struct CmdSessionCache {
    double last_parsed_mtime = 0.0;
    CmdParsedInfo info;
    std::string last_completed_msg_id;
    double completion_time = 0.0;
    double last_active_time = 0.0;
};

static std::map<std::string, CmdSessionCache> cmd_cache;
static std::vector<std::pair<std::string, double>> g_cached_cmd_sessions;
static double g_last_cmd_scan_time = 0.0;

AgentState analyze_cmd_session(int pid, const std::string& session_file, double idle_timeout) {
    AgentState res;
    res.open = true;
    res.active = false;
    res.state = "idle";
    res.action = "Standing by";
    res.subtext = "Terminal Ready";
    res.message = "Standing by in terminal. Ready for orders.";
    res.priority = 1;
    
    if (session_file.empty() || !fs::exists(session_file)) {
        return res;
    }
    
    double mtime = get_file_mtime(session_file);
    double now = now_sec();
    double age = now - mtime;
    res.mtime = mtime;
    
    std::string session_key = session_file;
    if (cmd_cache.find(session_key) == cmd_cache.end()) {
        cmd_cache[session_key] = CmdSessionCache();
        cmd_cache[session_key].last_active_time = (age > 10.0 ? mtime : now);
    }
    auto& cache = cmd_cache[session_key];
    
    // Only re-parse file when mtime changed
    if (mtime != cache.last_parsed_mtime) {
        cache.last_parsed_mtime = mtime;
        cache.info = CmdParsedInfo();
        
        auto lines = read_last_lines(session_file, 60);
        if (!lines.empty()) {
            Json::CharReaderBuilder reader_builder;
            Json::Value last_entry;
            Json::Value last_assistant_entry;
            Json::Value last_user_entry;
            std::set<std::string> returned_tool_ids;
            
            for (auto it = lines.rbegin(); it != lines.rend(); ++it) {
                Json::Value entry;
                std::string errs;
                std::istringstream iss(*it);
                if (Json::parseFromStream(reader_builder, iss, &entry, &errs)) {
                    if (last_entry.isNull()) last_entry = entry;
                    
                    auto msg = entry.get("message", Json::Value());
                    std::string role = msg.get("role", "").asString();
                    
                    if (role == "user") {
                        if (last_user_entry.isNull()) last_user_entry = entry;
                        if (msg.isMember("content") && msg["content"].isArray()) {
                            for (const auto& c : msg["content"]) {
                                if (c.isObject() && c.get("type", "").asString() == "tool_result") {
                                    std::string tid = c.get("tool_use_id", "").asString();
                                    if (!tid.empty()) returned_tool_ids.insert(tid);
                                }
                            }
                        }
                    } else if (role == "assistant") {
                        if (last_assistant_entry.isNull()) last_assistant_entry = entry;
                    }
                    
                    if (cache.info.thought_msg.empty() && msg.isMember("content") && msg["content"].isArray()) {
                        for (const auto& c : msg["content"]) {
                            if (c.isObject()) {
                                std::string ctype = c.get("type", "").asString();
                                if (ctype == "thinking" && c.isMember("thinking")) {
                                    cache.info.thought_msg = clean_thought_sentence(c["thinking"].asString());
                                } else if (ctype == "text" && role == "assistant") {
                                    std::string txt = c.get("text", "").asString();
                                    if (txt.rfind("I'm ", 0) == 0 || txt.rfind("I will ", 0) == 0 || txt.rfind("Let's ", 0) == 0 || txt.rfind("I am ", 0) == 0) {
                                        cache.info.thought_msg = clean_thought_sentence(txt);
                                    }
                                }
                            }
                        }
                    }
                }
            }
            
            cache.info.last_entry_id = last_entry.isMember("id") ? last_entry["id"].asString() : std::to_string(lines.size());
            cache.info.last_role = last_entry.get("message", Json::Value()).get("role", "").asString();
            auto last_content = last_entry.get("message", Json::Value()).get("content", Json::arrayValue);
            
            for (const auto& c : last_content) {
                if (c.isObject() && c.get("type", "").asString() == "tool_result") {
                    cache.info.last_is_tool_result = true;
                    break;
                }
            }
            
            std::vector<Json::Value> pending_tools;
            if (!last_assistant_entry.isNull()) {
                auto asst_content = last_assistant_entry.get("message", Json::Value()).get("content", Json::arrayValue);
                for (const auto& c : asst_content) {
                    if (c.isObject() && c.get("type", "").asString() == "tool_use") {
                        std::string tid = c.get("id", "").asString();
                        if (tid.empty() || returned_tool_ids.find(tid) == returned_tool_ids.end()) {
                            pending_tools.push_back(c);
                        }
                    }
                }
            }
            
            if (!pending_tools.empty()) {
                cache.info.has_pending_tools = true;
                auto tc = pending_tools.back();
                cache.info.pending_tool_name = tc.get("name", "tool").asString();
                auto tool_input = tc.get("input", Json::Value());
                std::string fp = tool_input.get("file_path", "").asString();
                if (fp.empty()) fp = tool_input.get("path", "").asString();
                cache.info.pending_tool_file = fp;
                
                std::string fname = fp.empty() ? "" : fs::path(fp).filename().string();
                cache.info.pending_is_plan = (fp.find(".commandcode/plans") != std::string::npos || fp.find("/plans/") != std::string::npos || fname.find("plan") != std::string::npos);
                
                std::string tool_name = cache.info.pending_tool_name;
                if (tool_name == "todo_write") {
                    cache.info.pending_tool_action = "Updating plan";
                } else if (tool_name == "enter_plan_mode" || tool_name == "exit_plan_mode" || tool_name == "plan_review" || cache.info.pending_is_plan) {
                    cache.info.pending_tool_action = "Planning";
                } else if (tool_name == "edit_file" || tool_name == "write_file" || tool_name == "patch_file") {
                    cache.info.pending_tool_action = fname.empty() ? "Editing file" : "Editing " + fname;
                } else if (tool_name == "read_file" || tool_name == "view_file") {
                    cache.info.pending_tool_action = fname.empty() ? "Reading file" : "Reading " + fname;
                } else if (tool_name == "grep" || tool_name == "find" || tool_name == "glob") {
                    cache.info.pending_tool_action = "Searching codebase";
                } else if (tool_name == "web_search" || tool_name == "web_fetch") {
                    cache.info.pending_tool_action = "Searching web";
                } else if (tool_name == "shell_command") {
                    std::string desc = tool_input.get("description", "").asString();
                    if (desc.empty()) desc = tool_input.get("command", "").asString();
                    cache.info.pending_tool_action = desc.empty() ? "Running shell" : desc;
                } else {
                    cache.info.pending_tool_action = tool_name;
                }
                if (cache.info.pending_tool_action.length() > 30) {
                    cache.info.pending_tool_action = cache.info.pending_tool_action.substr(0, 27) + "...";
                }
            }
            
            if (cache.info.last_role == "assistant") {
                std::string last_txt;
                for (const auto& c : last_content) {
                    if (c.isObject() && c.get("type", "").asString() == "text") {
                        last_txt += c.get("text", "").asString() + " ";
                    }
                }
                std::transform(last_txt.begin(), last_txt.end(), last_txt.begin(), ::tolower);
                if (last_txt.find("[y/n]") != std::string::npos || 
                    last_txt.find("continue?") != std::string::npos || 
                    last_txt.find("proceed?") != std::string::npos || 
                    last_txt.find("confirm") != std::string::npos || 
                    last_txt.find("switch to model") != std::string::npos || 
                    last_txt.find("choice:") != std::string::npos || 
                    last_txt.find("select an option") != std::string::npos ||
                    last_txt.find("type 'yes'") != std::string::npos) {
                    cache.info.assistant_asking_option = true;
                }
            }
        }
    }
    
    static const std::set<std::string> PLAN_TOOLS = {
        "enter_plan_mode", "exit_plan_mode", "todo_write", "plan_review", "create_plan", "plan", "todo"
    };
    static const std::set<std::string> ANALYSIS_TOOLS = {
        "read_file", "view_file", "grep", "find", "list_dir", "read_directory", "glob",
        "web_search", "web_fetch", "taste", "activate_skill", "fetch_web_page", "search_code",
        "codebase_search", "directory_list", "agent", "agent_output"
    };
    static const std::set<std::string> TASK_TOOLS = {
        "edit_file", "write_file", "create_file", "replace_file_content", "patch_file",
        "shell_command", "bash", "run_command", "execute_command", "save_file", "apply_diff",
        "kill_shell", "shell_output", "shell_tasks"
    };
    static const std::set<std::string> WAITING_TOOLS = {
        "ask_user_question", "ask_question", "confirm", "prompt", "user_input", "wait_task", "request_feedback", "sleep"
    };
    
    // 1. ACTIVE TOOL EXECUTION / PLANNING / WAITING
    if (cache.info.has_pending_tools && age < 120.0) {
        std::string tool_name = cache.info.pending_tool_name;
        std::string action_text = cache.info.pending_tool_action;
        
        cache.last_active_time = now;
        cache.completion_time = 0.0;
        
        if (PLAN_TOOLS.count(tool_name) || cache.info.pending_is_plan) {
            // Plan Mode
            res.active = true;
            res.state = "thinking";
            res.action = action_text;
            res.subtext = "Plan Mode";
            res.message = cache.info.thought_msg.empty() ? "Formulating task execution plan..." : cache.info.thought_msg;
            res.priority = 4;
            return res;
        } else if (WAITING_TOOLS.count(tool_name)) {
            // Waiting for option / confirmation
            res.active = true;
            res.state = "waiting";
            res.action = "Waiting for option";
            res.subtext = "Waiting";
            res.message = cache.info.thought_msg.empty() ? "Awaiting your option / confirmation in terminal..." : cache.info.thought_msg;
            res.priority = 4;
            return res;
        } else if (TASK_TOOLS.count(tool_name)) {
            // Doing a Task / Execution
            res.active = true;
            res.state = "working";
            res.action = action_text;
            res.subtext = "Doing Task";
            res.message = cache.info.thought_msg.empty() ? "Executing " + tool_name + " in workspace..." : cache.info.thought_msg;
            res.priority = 5;
            return res;
        } else if (ANALYSIS_TOOLS.count(tool_name)) {
            // Analysis / Reading
            res.active = true;
            res.state = "thinking";
            res.action = action_text;
            res.subtext = "Analysis";
            res.message = cache.info.thought_msg.empty() ? "Analyzing parameters with " + tool_name + "..." : cache.info.thought_msg;
            res.priority = 3;
            return res;
        } else {
            res.active = true;
            res.state = "thinking";
            res.action = action_text;
            res.subtext = "Analysis";
            res.message = cache.info.thought_msg.empty() ? "Processing tactical step..." : cache.info.thought_msg;
            res.priority = 3;
            return res;
        }
    }
    
    // 2. TOOL JUST RETURNED RESULT -> MODEL IS ACTIVELY THINKING / GENERATING
    if (cache.info.last_is_tool_result && age < 60.0) {
        cache.last_active_time = now;
        cache.completion_time = 0.0;
        res.active = true;
        res.state = "thinking";
        res.action = "Analyzing results";
        res.subtext = "Analysis";
        res.message = cache.info.thought_msg.empty() ? "Processing tool results..." : cache.info.thought_msg;
        res.priority = 3;
        return res;
    }
    
    // 3. USER PROMPT RECENTLY SUBMITTED -> MODEL IS THINKING / FORMULATING
    if (cache.info.last_role == "user" && !cache.info.last_is_tool_result && age < 15.0) {
        cache.last_active_time = now;
        cache.completion_time = 0.0;
        res.active = true;
        res.state = "thinking";
        res.action = "Formulating plan";
        res.subtext = "Plan Mode";
        res.message = cache.info.thought_msg.empty() ? "Formulating plan for terminal request..." : cache.info.thought_msg;
        res.priority = 3;
        return res;
    }
    
    // 4. ASSISTANT ASKING FOR CONFIRMATION / OPTION IN TEXT
    if (cache.info.last_role == "assistant" && cache.info.assistant_asking_option && age < 300.0) {
        cache.last_active_time = now;
        cache.completion_time = 0.0;
        res.active = true;
        res.state = "waiting";
        res.action = "Waiting for option";
        res.subtext = "Waiting";
        res.message = cache.info.thought_msg.empty() ? "Awaiting your option / confirmation in terminal..." : cache.info.thought_msg;
        res.priority = 4;
        return res;
    }
    
    // 5. TURN COMPLETE / SUCCESS CELEBRATION (8 seconds)
    std::string msg_id = cache.info.last_entry_id;
    if (msg_id != cache.last_completed_msg_id) {
        cache.last_completed_msg_id = msg_id;
        if (age < 8.0) {
            cache.completion_time = now;
            cache.last_active_time = now;
        } else {
            cache.completion_time = 0.0;
            cache.last_active_time = mtime;
        }
    }
    
    if (cache.completion_time > 0.0 && (now - cache.completion_time < 8.0)) {
        res.active = true;
        res.state = "success";
        res.action = "Task Complete";
        res.subtext = "Success";
        res.message = "Mission complete! Terminal task accomplished.";
        res.priority = 2;
        return res;
    }
    
    // 6. IDLE / SLEEP TRANSITION (<5s idle -> >=5s sleeping)
    double idle_dur = now - std::max(cache.completion_time > 0.0 ? cache.completion_time + 8.0 : 0.0, cache.last_active_time);
    if (idle_dur > idle_timeout) {
        res.open = false;
        res.state = "idle";
        res.subtext = "Offline (Idle)";
        res.priority = 0;
    } else if (idle_dur > NAP_IDLE_SECONDS) {
        res.state = "sleeping";
        res.action = "Taking a nap";
        res.subtext = "Titans Resting";
        res.message = "Taking a breather at Titans Tower. (Zzz...)";
        res.priority = 0;
    } else {
        res.state = "idle";
        res.action = "Standing by";
        res.subtext = "Terminal Ready";
        res.message = "Standing by in terminal. Ready for orders.";
        res.priority = 1;
    }
    return res;
}

AgentState get_cmd_status(double idle_timeout) {
    auto pids = get_cached_pids("command-code");
    if (pids.empty()) {
        pids = get_cached_pids("bin/cmd");
    }
    
    if (pids.empty()) {
        AgentState s;
        s.open = false;
        s.active = false;
        s.state = "idle";
        s.action = "Standing by";
        s.subtext = "Offline";
        s.message = "Standing by in terminal.";
        return s;
    }
    
    int pid = pids[0];
    double now = now_sec();
    
    if (now - g_last_cmd_scan_time > 1.5 || g_cached_cmd_sessions.empty()) {
        g_last_cmd_scan_time = now;
        g_cached_cmd_sessions.clear();
        
        std::string cwd = get_process_cwd(pid);
        std::string proj_base = get_home_dir() + "/.commandcode/projects";
        
        // First, try matching CWD to project folder
        std::string target_proj_folder;
        if (!cwd.empty()) {
            std::string mangled = cwd;
            if (!mangled.empty() && mangled[0] == '/') mangled = mangled.substr(1);
            std::replace(mangled.begin(), mangled.end(), '/', '-');
            std::string ppath = proj_base + "/" + mangled;
            if (fs::exists(ppath)) {
                target_proj_folder = ppath;
            }
        }
        
        if (!target_proj_folder.empty()) {
            for (const auto& fentry : fs::directory_iterator(target_proj_folder)) {
                std::string fpath = fentry.path().string();
                if (fpath.length() > 6 && fpath.substr(fpath.length() - 6) == ".jsonl" && 
                    fpath.find(".checkpoints.jsonl") == std::string::npos) {
                    g_cached_cmd_sessions.push_back({fpath, get_file_mtime(fpath)});
                }
            }
        }
        
        // If no session found in target folder, scan all projects
        if (g_cached_cmd_sessions.empty() && fs::exists(proj_base)) {
            for (const auto& pentry : fs::directory_iterator(proj_base)) {
                if (pentry.is_directory()) {
                    for (const auto& fentry : fs::directory_iterator(pentry.path())) {
                        std::string fpath = fentry.path().string();
                        if (fpath.length() > 6 && fpath.substr(fpath.length() - 6) == ".jsonl" && 
                            fpath.find(".checkpoints.jsonl") == std::string::npos) {
                            g_cached_cmd_sessions.push_back({fpath, get_file_mtime(fpath)});
                        }
                    }
                }
            }
        }
        
        std::sort(g_cached_cmd_sessions.begin(), g_cached_cmd_sessions.end(), [](const auto& a, const auto& b) {
            return a.second > b.second;
        });
    }
    
    if (g_cached_cmd_sessions.empty()) {
        AgentState s;
        s.open = true;
        s.active = false;
        s.state = "idle";
        s.action = "Standing by";
        s.subtext = "Terminal Ready";
        s.message = "Standing by in terminal. Ready for orders.";
        return s;
    }
    
    return analyze_cmd_session(pid, g_cached_cmd_sessions[0].first, idle_timeout);
}

// ==============================================================================
// MAIN DAEMON LOOP
// ==============================================================================

int main() {
    std::string last_written;
    Json::StreamWriterBuilder writer_builder;
    writer_builder["indentation"] = "";
    
    while (true) {
        try {
            double idle_timeout = DEFAULT_IDLE_TIMEOUT;
            
            AgentState agy = get_agy_status(idle_timeout);
            AgentState cmd = get_cmd_status(idle_timeout);
            
            Json::Value root;
            root["enabled"] = true;
            
            root["agy"]["open"] = agy.open;
            root["agy"]["active"] = agy.active;
            root["agy"]["state"] = agy.state;
            root["agy"]["action"] = agy.action;
            root["agy"]["subtext"] = agy.subtext;
            root["agy"]["message"] = agy.message;
            
            root["cmd"]["open"] = cmd.open;
            root["cmd"]["active"] = cmd.active;
            root["cmd"]["state"] = cmd.state;
            root["cmd"]["action"] = cmd.action;
            root["cmd"]["subtext"] = cmd.subtext;
            root["cmd"]["message"] = cmd.message;
            
            std::string raw = Json::writeString(writer_builder, root);
            if (raw != last_written) {
                std::ofstream out(STATE_FILE);
                if (out.is_open()) {
                    out << raw;
                    out.close();
                }
                last_written = raw;
            }
        } catch (...) {}
        
        std::this_thread::sleep_for(std::chrono::milliseconds(100));
    }
    return 0;
}
