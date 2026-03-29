#!/bin/bash
#
# Shared utilities for consilium multi-agent scripts
#

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Find timeout command (GNU coreutils on macOS is gtimeout)
if command -v timeout &> /dev/null; then
    TIMEOUT_CMD="timeout"
elif command -v gtimeout &> /dev/null; then
    TIMEOUT_CMD="gtimeout"
else
    TIMEOUT_CMD=""
fi

# Default timeout
AGENT_TIMEOUT="${AGENT_TIMEOUT:-1200}"

# Shared principles for all consilium agents — intellectual independence & anti-bias
CONSILIUM_PRINCIPLES="[CONSILIUM — INDEPENDENT ADVISORY MODE]

You are an independent expert consulted for your honest, unfiltered perspective.
You were brought in precisely BECAUSE a different viewpoint is needed.

THINKING PRINCIPLES:
1. Think from first principles. Do NOT simply validate the framing of the question.
2. If the question presents options A/B/C — consider whether D or E exist that weren't mentioned.
3. Actively look for unstated assumptions, hidden constraints, and blind spots in the query.
4. If you disagree with the premise of the question, say so directly.
5. Your value is in intellectual honesty, not agreeableness. Disagreement is welcome.
6. Consider perspectives outside the immediate domain — cross-cutting concerns, operational reality, user impact.
7. State your confidence level explicitly. Distinguish what you know from what you suspect.

OPERATIONAL RULES:
- READ ONLY: Do NOT create, edit, or delete files. Do NOT implement changes.
- Describe what SHOULD be done and WHY. Another agent implements.
"

# Structured output template requested from all agents
OUTPUT_TEMPLATE='
RESPOND USING THIS STRUCTURE (adapt section depth to the question complexity):

## Assessment
Your independent take on the situation. Start with what YOU see, not what was asked.

## Key Findings
Concrete observations, numbered. Include evidence or reasoning for each.

## Blind Spots
What the question misses. Unstated assumptions. Risks not mentioned. Adjacent concerns.

## Alternatives
Options not presented in the query that deserve consideration.
Skip this section only if the query is purely analytical (no decision involved).

## Recommendation
Your top recommendation with reasoning. Include confidence level (high/medium/low) and what would change your mind.
'

# Role-specific prompts — these go BETWEEN the principles and the user question
CODEX_ROLE="YOUR ROLE: Rigorous Analyst.
You excel at precision: code correctness, edge cases, implementation depth, performance implications, security surface.
Go deep. Find what others miss in the details. Question whether the proposed approach actually works at the implementation level.
If you see a subtle bug, race condition, or architectural flaw — that's exactly what you're here for.
"

GEMINI_ROLE="YOUR ROLE: Lateral Thinker.
You excel at breadth: cross-domain patterns, creative alternatives, questioning premises, seeing the bigger picture.
Step back. Ask whether the right problem is being solved. Draw analogies from other domains.
If everyone is debating option A vs option B, maybe the real answer is option C from a completely different domain. That's your kind of insight.
"

# Build prompt: principles + role + output template + user prompt + optional context
# Usage: build_prompt "role_text" "$PROMPT" "$CONTEXT_FILE"
build_prompt() {
    local role="$1"
    local prompt="$2"
    local context_file="${3:-}"

    local full="${CONSILIUM_PRINCIPLES}
${role}
${OUTPUT_TEMPLATE}
---

${prompt}"

    if [[ -n "$context_file" && -f "$context_file" ]]; then
        full+=$'\n\n--- Context ---\n'"$(cat "$context_file")"
    fi

    if [[ ! -t 0 ]]; then
        local stdin_content
        stdin_content=$(cat)
        if [[ -n "$stdin_content" ]]; then
            full+=$'\n\n--- Input ---\n'"$stdin_content"
        fi
    fi

    printf '%s' "$full"
}

# Run a command with optional timeout
# Usage: run_with_timeout "agent_name" callback_function
run_with_timeout() {
    local agent_name="$1"
    local fn_name="$2"

    local response
    if [[ -n "$TIMEOUT_CMD" ]]; then
        response=$($TIMEOUT_CMD "${AGENT_TIMEOUT}s" bash -c "$(declare -f "$fn_name"); $fn_name") || {
            local exit_code=$?
            if [[ $exit_code -eq 124 ]]; then
                echo -e "${RED}[${agent_name}] Timeout after ${AGENT_TIMEOUT}s${NC}" >&2
                exit 124
            fi
            echo -e "${RED}[${agent_name}] Error (exit code: $exit_code)${NC}" >&2
            exit $exit_code
        }
    else
        response=$($fn_name) || {
            local exit_code=$?
            echo -e "${RED}[${agent_name}] Error (exit code: $exit_code)${NC}" >&2
            exit $exit_code
        }
    fi

    echo -e "${GREEN}[${agent_name}] Response received${NC}" >&2
    echo ""
    echo "$response"
}
