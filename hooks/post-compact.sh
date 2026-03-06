#!/usr/bin/env bash
# SessionStart(compact) hook: load handoff -> inject as additionalContext
set -euo pipefail

INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('session_id',''))" 2>/dev/null)

if [ -z "$SESSION_ID" ]; then
    exit 0
fi

HANDOFF_FILE="$HOME/.claude/autohandoff/${SESSION_ID}.json"
if [ ! -f "$HANDOFF_FILE" ]; then
    exit 0
fi

_HANDOFF_FILE="$HANDOFF_FILE" python3 << 'PYEOF'
import json, os, sys

handoff_file = os.environ["_HANDOFF_FILE"]
try:
    with open(handoff_file, "r") as f:
        handoff = json.load(f)
except Exception:
    sys.exit(0)

lines = ["=== PRE-COMPACT CONTEXT (auto-recovered) ===", ""]

orig = handoff.get("original_request", "")
if orig:
    lines += ["## Original Request", orig, ""]

trigger = handoff.get("trigger", "unknown")
total = handoff.get("total_messages", 0)
compact_count = handoff.get("compact_count", 0)
lines += ["## Session Info",
          f"- Trigger: {trigger} | Messages before compact: {total} | Previous compacts: {compact_count}",
          f"- Working directory: {handoff.get('cwd', 'unknown')}", ""]

for title, key in [("## Recent User Messages (latest 3)", "recent_user_messages"),
                    ("## Recent Assistant Responses (latest 5)", "recent_assistant_texts")]:
    items = handoff.get(key, [])
    if items:
        lines.append(title)
        for i, msg in enumerate(items, 1):
            lines.append(f"{i}. {msg}")
        lines.append("")

tool_uses = handoff.get("recent_tool_uses", [])
if tool_uses:
    lines.append("## Recent Tool Uses (latest 10)")
    for t in tool_uses:
        lines.append(f"- {t.get('name', '?')}: {t.get('input_summary', '')[:150]}")
    lines.append("")

lines.append("=== END PRE-COMPACT CONTEXT ===")

output = {"hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": "\n".join(lines)}}
print(json.dumps(output))
PYEOF
