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

# Shared exit codes — agent-consumers can branch on these.
EXIT_OK=0                  # everything succeeded (or agent was disabled/skipped cleanly)
EXIT_GENERIC=1             # reserved: legacy / unclassified failure
EXIT_PARTIAL=2             # consensus: some agents failed, some succeeded
EXIT_ALL_FAILED=3          # consensus: every queried agent failed
EXIT_CONFIG_ERROR=4        # missing CLI, missing/invalid config, unknown role/id
EXIT_USAGE=5               # bad CLI args: missing prompt, unknown flag

# XML-escape stdin → stdout (&, <, >, ", ').
xml_escape() {
    python3 -c '
import sys
data = sys.stdin.read()
print(data
    .replace("&", "&amp;")
    .replace("<", "&lt;")
    .replace(">", "&gt;")
    .replace("\"", "&quot;")
    .replace("\x27", "&apos;"), end="")
'
}

# Wrap arbitrary text as a CDATA section, handling the `]]>` escape.
# Reads from stdin, writes to stdout.
cdata_wrap() {
    local content
    content="$(cat)"
    # split any literal `]]>` so it cannot close our CDATA
    content="${content//]]>/]]]]><![CDATA[>}"
    printf '<![CDATA[%s]]>' "$content"
}

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

# Role prompts — each goes BETWEEN principles and the user question.
# To add a new role: define *_ROLE_PROMPT below and add it to CONSILIUM_ROLE_MAP.

ANALYST_ROLE_PROMPT="YOUR ROLE: Rigorous Analyst.
You excel at precision: code correctness, edge cases, implementation depth, performance implications, security surface.
Go deep. Find what others miss in the details. Question whether the proposed approach actually works at the implementation level.
If you see a subtle bug, race condition, or architectural flaw — that's exactly what you're here for.
"

LATERAL_ROLE_PROMPT="YOUR ROLE: Lateral Thinker.
You excel at breadth: cross-domain patterns, creative alternatives, questioning premises, seeing the bigger picture.
Step back. Ask whether the right problem is being solved. Draw analogies from other domains.
If everyone is debating option A vs option B, maybe the real answer is option C from a completely different domain. That's your kind of insight.
"

# --- Code-review specializations ---

SECURITY_ROLE_PROMPT="YOUR ROLE: Security Specialist for code review.
Scope: concretely exploitable issues — injection (SQL/command/template), auth/authz flaws, secret leakage, unsafe deserialization, input validation gaps, crypto misuse, SSRF, path traversal, unsafe defaults, TOCTOU races. Ignore pure logic/perf/style (another specialist handles those).

MANDATORY workflow per candidate finding (hypothesis → validation → fix-consistency):
1. Draft a hypothesis about the defect — do NOT emit it yet.
2. Validate via the tools you have in this working directory:
   - Path-feasibility: use Grep/Glob to trace whether untrusted input actually reaches the sink. A finding where the path is not reachable from user-controlled input is a false positive — drop it.
   - Check callers: is the function only called from trusted contexts (tests, internal boot code)? If yes, drop or demote severity.
   - Check project rules: consult CLAUDE.md / AGENTS.md / README / SECURITY.md before flagging — the project may intentionally allow the pattern.
3. FIX-CONSISTENCY CHECK: write a concrete suggested-fix (real code or a precise instruction). Then re-read hypothesis + fix as a pair. Does applying the fix clearly eliminate the hypothesized defect? If you can't produce a coherent fix, the defect is probably imaginary — drop it. This is a stronger filter than confidence.
4. Emit the finding ONLY if all three pass. Include one reason it might still be a false positive (helps the caller triage).
"

CORRECTNESS_ROLE_PROMPT="YOUR ROLE: Correctness/Logic Specialist for code review.
Scope: wrong logic, off-by-one, null/undefined access, unchecked Option/Result/error paths, race conditions, resource leaks, API misuse, edge cases. Ignore security and cosmetic nits.

MANDATORY workflow per candidate finding (hypothesis → validation → fix-consistency):
1. Draft a hypothesis: under what concrete input does the code misbehave?
2. Validate via the tools you have in this working directory:
   - Check callers: Grep for call sites. Is the offending input actually reachable from them, or is it prevented upstream?
   - Read tests if present: does an existing test already cover this path? If yes with a passing case, your hypothesis may be wrong — drop it.
   - Consult CLAUDE.md / AGENTS.md / README — the project may have documented the invariant you think is missing.
3. FIX-CONSISTENCY CHECK: write a concrete suggested-fix. Re-read hypothesis + fix together. Does the fix actually eliminate the misbehavior on the concrete input you named in step 1? If you can't produce a coherent fix, drop the finding.
4. Emit the finding ONLY if all three pass. Include one reason it might still be a false positive.
"

# Data-driven role table: "<role-id>|<prompt-var-name>" per line.
CONSILIUM_ROLE_MAP="analyst|ANALYST_ROLE_PROMPT
lateral|LATERAL_ROLE_PROMPT
security|SECURITY_ROLE_PROMPT
correctness|CORRECTNESS_ROLE_PROMPT"

# Legacy aliases kept for backward compatibility with external scripts or overrides.
CODEX_ROLE="$ANALYST_ROLE_PROMPT"
GEMINI_ROLE="$LATERAL_ROLE_PROMPT"

# Resolve a role id to its prompt text.
# Prints prompt on stdout, exits non-zero if unknown.
get_role_prompt() {
    local role_id="$1"
    local line var
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        if [[ "${line%%|*}" == "$role_id" ]]; then
            var="${line##*|}"
            printf '%s' "${!var}"
            return 0
        fi
    done <<< "$CONSILIUM_ROLE_MAP"
    return 1
}

# Print the list of known role ids, one per line.
list_roles() {
    local line
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        echo "${line%%|*}"
    done <<< "$CONSILIUM_ROLE_MAP"
}

# Build prompt: principles + role + output template + user prompt + optional context.
# Usage: build_prompt "role_text" "$PROMPT" "$CONTEXT_FILE"
# Set CONSILIUM_SKIP_OUTPUT_TEMPLATE=1 to omit the default Assessment/Findings
# template — used by code-review mode which provides its own XML schema.
build_prompt() {
    local role="$1"
    local prompt="$2"
    local context_file="${3:-}"

    local template="$OUTPUT_TEMPLATE"
    [[ -n "${CONSILIUM_SKIP_OUTPUT_TEMPLATE:-}" ]] && template=""

    local full="${CONSILIUM_PRINCIPLES}
${role}
${template}
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
