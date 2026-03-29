#!/bin/bash
#
# Consensus Query - Get opinions from both Codex and Gemini
# Usage: ./consensus-query.sh "question"
#        cat file.ts | ./consensus-query.sh "review this code"
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

CODEX_MODEL="${CODEX_MODEL:-gpt-5.4}"
GEMINI_MODEL="${GEMINI_MODEL:-gemini-3.1-pro-preview}"

PROMPT="${1:-}"

if [[ -z "$PROMPT" ]]; then
    echo -e "${RED}Error: No prompt provided${NC}" >&2
    echo "Usage: $0 \"question\"" >&2
    exit 1
fi

# Capture piped input if any
STDIN_CONTENT=""
if [[ ! -t 0 ]]; then
    STDIN_CONTENT=$(cat)
fi

CODEX_OUT=$(mktemp)
GEMINI_OUT=$(mktemp)
trap "rm -f $CODEX_OUT $GEMINI_OUT" EXIT

echo -e "${CYAN}  CONSENSUS QUERY - Querying Codex + Gemini in parallel${NC}" >&2
echo "" >&2

echo -e "${YELLOW}[Launching parallel queries...]${NC}" >&2

if [[ -n "$STDIN_CONTENT" ]]; then
    echo "$STDIN_CONTENT" | "$SCRIPT_DIR/codex-query.sh" "$PROMPT" > "$CODEX_OUT" 2>&1 &
    CODEX_PID=$!
    echo "$STDIN_CONTENT" | "$SCRIPT_DIR/gemini-query.sh" "$PROMPT" > "$GEMINI_OUT" 2>&1 &
    GEMINI_PID=$!
else
    "$SCRIPT_DIR/codex-query.sh" "$PROMPT" > "$CODEX_OUT" 2>&1 &
    CODEX_PID=$!
    "$SCRIPT_DIR/gemini-query.sh" "$PROMPT" > "$GEMINI_OUT" 2>&1 &
    GEMINI_PID=$!
fi

CODEX_EXIT=0
GEMINI_EXIT=0
wait $CODEX_PID || CODEX_EXIT=$?
wait $GEMINI_PID || GEMINI_EXIT=$?

echo ""
echo "## Codex Response (${CODEX_MODEL})"
echo ""
if [[ $CODEX_EXIT -eq 0 ]]; then
    cat "$CODEX_OUT"
else
    echo "[Codex query failed with exit code $CODEX_EXIT]"
    cat "$CODEX_OUT"
fi

echo ""
echo "## Gemini Response (${GEMINI_MODEL})"
echo ""
if [[ $GEMINI_EXIT -eq 0 ]]; then
    cat "$GEMINI_OUT"
else
    echo "[Gemini query failed with exit code $GEMINI_EXIT]"
    cat "$GEMINI_OUT"
fi

echo ""
echo "---"
echo "END OF CONSENSUS REPORT"

if [[ $CODEX_EXIT -ne 0 && $GEMINI_EXIT -ne 0 ]]; then
    exit 1
fi
