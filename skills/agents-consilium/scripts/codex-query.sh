#!/bin/bash
#
# Codex CLI Wrapper for Consilium — Rigorous Analyst role
# Usage: ./codex-query.sh "prompt" [context_file]
#        cat file.ts | ./codex-query.sh "analyze this"
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

MODEL="${CODEX_MODEL:-gpt-5.4}"

if ! command -v codex &> /dev/null; then
    echo -e "${RED}Error: Codex CLI is not installed${NC}" >&2
    echo "Install from: https://github.com/openai/codex" >&2
    exit 1
fi

PROMPT="${1:-}"
CONTEXT_FILE="${2:-}"

if [[ -z "$PROMPT" ]]; then
    echo -e "${RED}Error: No prompt provided${NC}" >&2
    echo "Usage: $0 \"prompt\" [context_file]" >&2
    exit 1
fi

FULL_PROMPT=$(build_prompt "$CODEX_ROLE" "$PROMPT" "$CONTEXT_FILE")

echo -e "${YELLOW}[Codex] Querying ${MODEL} (Rigorous Analyst)...${NC}" >&2

export CODEX_TMPOUT=$(mktemp)
trap "rm -f $CODEX_TMPOUT" EXIT

run_codex() {
    codex exec \
        --model "$MODEL" \
        --sandbox read-only \
        --skip-git-repo-check \
        --ephemeral \
        -o "$CODEX_TMPOUT" \
        "$FULL_PROMPT" >/dev/null 2>&1
    cat "$CODEX_TMPOUT"
}

run_with_timeout "Codex" run_codex
