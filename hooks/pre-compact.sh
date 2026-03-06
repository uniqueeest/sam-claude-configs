#!/usr/bin/env bash
# PreCompact hook: parse transcript -> save handoff context for post-compact recovery
set -euo pipefail

INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('session_id',''))" 2>/dev/null)
TRANSCRIPT_PATH=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('transcript_path',''))" 2>/dev/null)
TRIGGER=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('trigger','unknown'))" 2>/dev/null)
CWD=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('cwd',''))" 2>/dev/null)

if [ -z "$SESSION_ID" ] || [ -z "$TRANSCRIPT_PATH" ] || [ ! -f "$TRANSCRIPT_PATH" ]; then
    exit 0
fi

HANDOFF_DIR="$HOME/.claude/autohandoff"
mkdir -p "$HANDOFF_DIR"

_SESSION_ID="$SESSION_ID" _TRANSCRIPT_PATH="$TRANSCRIPT_PATH" _TRIGGER="$TRIGGER" _CWD="$CWD" _HANDOFF_DIR="$HANDOFF_DIR" python3 << 'PYEOF'
import json, sys, os
from collections import deque
from datetime import datetime

session_id = os.environ["_SESSION_ID"]
transcript_path = os.environ["_TRANSCRIPT_PATH"]
trigger = os.environ.get("_TRIGGER", "unknown")
cwd = os.environ.get("_CWD", "")
handoff_dir = os.environ["_HANDOFF_DIR"]

first_user_msg = None
recent_user_msgs = deque(maxlen=3)
recent_assistant_texts = deque(maxlen=5)
recent_tool_uses = deque(maxlen=10)
compact_count = 0
total_messages = 0

def extract_text(content, max_len=500):
    if isinstance(content, str):
        return content[:max_len]
    if isinstance(content, list):
        parts = []
        for item in content:
            if isinstance(item, dict):
                if item.get("type") == "text":
                    parts.append(item.get("text", ""))
                elif item.get("type") == "tool_use":
                    tool_input = item.get("input", {})
                    input_summary = str(tool_input)[:200] if tool_input else ""
                    recent_tool_uses.append({"name": item.get("name", "unknown"), "input_summary": input_summary})
        return "\n".join(parts)[:max_len]
    return ""

try:
    with open(transcript_path, "r") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                obj = json.loads(line)
            except json.JSONDecodeError:
                continue
            msg_type = obj.get("type", "")
            total_messages += 1
            if msg_type == "summary" or obj.get("isSummary"):
                compact_count += 1
                continue
            if msg_type not in ("user", "assistant"):
                continue
            message = obj.get("message", {})
            role = message.get("role", msg_type)
            content = message.get("content", "")
            if role == "user":
                text = extract_text(content, 300)
                if text.strip():
                    if first_user_msg is None:
                        first_user_msg = text
                    recent_user_msgs.append(text)
            elif role == "assistant":
                text = extract_text(content, 500)
                if text.strip():
                    recent_assistant_texts.append(text)
except Exception:
    sys.exit(0)

handoff = {
    "session_id": session_id, "trigger": trigger, "cwd": cwd,
    "timestamp": datetime.now().isoformat(),
    "total_messages": total_messages, "compact_count": compact_count,
    "original_request": first_user_msg or "",
    "recent_user_messages": list(recent_user_msgs),
    "recent_assistant_texts": list(recent_assistant_texts),
    "recent_tool_uses": list(recent_tool_uses),
}

output_path = os.path.join(handoff_dir, f"{session_id}.json")
with open(output_path, "w") as f:
    json.dump(handoff, f, ensure_ascii=False, indent=2)

# Auto-cleanup: keep only 20 most recent
files = [(os.path.getmtime(os.path.join(handoff_dir, fn)), os.path.join(handoff_dir, fn))
         for fn in os.listdir(handoff_dir) if fn.endswith(".json")]
files.sort(reverse=True)
for _, fpath in files[20:]:
    os.remove(fpath)
PYEOF
