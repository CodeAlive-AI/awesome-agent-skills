#!/bin/bash
#
# Codex CLI Wrapper for Consilium
# Role and model are read from config.json (agent id "codex").
#
# Usage: ./codex-query.sh "prompt" [context_file]
#        cat file.ts | ./codex-query.sh "analyze this"
#        ./codex-query.sh --help
#
# Exit codes:
#   0 — success, or agent disabled (skipped)
#   4 — config error (missing config, unknown role, CLI not installed)
#   5 — usage error (missing prompt or unknown flag)
#   other — propagated from codex CLI (e.g. 124 on timeout)
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
source "$SCRIPT_DIR/config.sh"

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    sed -n '2,14p' "$0"
    exit $EXIT_OK
fi

config_validate || exit $EXIT_CONFIG_ERROR

AGENT_ID="codex"

if ! config_is_enabled "$AGENT_ID"; then
    echo -e "${YELLOW}[Codex] Disabled in config ($CONSILIUM_CONFIG). Skipping.${NC}" >&2
    exit $EXIT_OK
fi

MODEL="${CODEX_MODEL:-$(config_get_field "$AGENT_ID" model)}"
ROLE_ID="${CONSILIUM_ROLE_OVERRIDE:-$(config_get_field "$AGENT_ID" role)}"
LABEL="$(config_get_field "$AGENT_ID" label)"
LABEL="${LABEL:-Codex}"

if ! ROLE_PROMPT="$(get_role_prompt "$ROLE_ID")"; then
    echo -e "${RED}Error: unknown role '$ROLE_ID' for codex in config${NC}" >&2
    exit $EXIT_CONFIG_ERROR
fi

if ! command -v codex &> /dev/null; then
    echo -e "${RED}Error: Codex CLI is not installed${NC}" >&2
    echo "Install from: https://github.com/openai/codex" >&2
    exit $EXIT_CONFIG_ERROR
fi

PROMPT="${1:-}"
CONTEXT_FILE="${2:-}"

if [[ -z "$PROMPT" ]]; then
    echo -e "${RED}Error: No prompt provided${NC}" >&2
    echo "Usage: $0 \"prompt\" [context_file]" >&2
    exit $EXIT_USAGE
fi

export FULL_PROMPT
FULL_PROMPT=$(build_prompt "$ROLE_PROMPT" "$PROMPT" "$CONTEXT_FILE")

echo -e "${YELLOW}[${LABEL}] Querying ${MODEL} (role=${ROLE_ID})...${NC}" >&2

export MODEL
export CODEX_TMPOUT=$(mktemp)
trap "rm -f $CODEX_TMPOUT" EXIT

run_codex() {
    # Runs in the caller's CWD so the agent can freely read the real project
    # (codebase search, git log, CLAUDE.md, etc.). Sandbox is pinned to
    # read-only so it cannot modify files; -a never keeps it non-interactive.
    local codex_stderr
    codex_stderr=$(mktemp)
    codex -a never exec \
        --model "$MODEL" \
        --sandbox read-only \
        --skip-git-repo-check \
        --ephemeral \
        -o "$CODEX_TMPOUT" \
        "$FULL_PROMPT" >/dev/null 2>"$codex_stderr"
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        echo "[Codex] Error (exit $exit_code):" >&2
        cat "$codex_stderr" >&2
    fi
    rm -f "$codex_stderr"
    cat "$CODEX_TMPOUT"
    return $exit_code
}

run_with_timeout "$LABEL" run_codex
