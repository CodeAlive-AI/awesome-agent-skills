#!/bin/bash
#
# Gemini CLI Wrapper for Consilium — Lateral Thinker role
# Usage: ./gemini-query.sh "prompt" [context_file]
#        cat file.ts | ./gemini-query.sh "analyze this"
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

MODEL="${GEMINI_MODEL:-gemini-3.1-pro-preview}"

if ! command -v gemini &> /dev/null; then
    echo -e "${RED}Error: Gemini CLI is not installed${NC}" >&2
    echo "Install from: https://geminicli.com" >&2
    exit 1
fi

PROMPT="${1:-}"
CONTEXT_FILE="${2:-}"

if [[ -z "$PROMPT" ]]; then
    echo -e "${RED}Error: No prompt provided${NC}" >&2
    echo "Usage: $0 \"prompt\" [context_file]" >&2
    exit 1
fi

FULL_PROMPT=$(build_prompt "$GEMINI_ROLE" "$PROMPT" "$CONTEXT_FILE")

echo -e "${YELLOW}[Gemini] Querying ${MODEL} (Lateral Thinker)...${NC}" >&2

run_gemini() {
    gemini \
        -p "$FULL_PROMPT" \
        --model "$MODEL" \
        --approval-mode yolo \
        --sandbox \
        -o text \
        -e "" \
        --allowed-mcp-server-names "" \
        2>/dev/null
}

run_with_timeout "Gemini" run_gemini
