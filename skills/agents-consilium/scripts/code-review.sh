#!/bin/bash
#
# Code Review Mode for Consilium
#
# Runs 2 specializations — Security and Correctness — across the enabled agents
# and returns findings with line anchors and a quoted-code check. There is no
# coordinator pass: the caller (you, or whatever agent invoked this) is expected
# to judge, dedup, and prioritize the findings.
#
# Usage:
#   code-review.sh <file>                  # review a single file on disk
#   code-review.sh --diff                  # read a unified diff from stdin
#   git diff HEAD | code-review.sh --diff  # same, piped
#   code-review.sh --xml <file>            # XML output (stable for agent consumers)
#   code-review.sh --help
#
# Options:
#   --diff               Treat input as a unified diff from stdin. Line anchors
#                        then refer to lines in the diff, not a specific file,
#                        and quoted-code validation is skipped.
#   --xml                Emit findings as <code-review-report> XML.
#                        Default is a markdown report grouped by severity.
#   -h, --help           Show this help.
#
# Behaviour:
#   - Specializations: security, correctness (research-backed pair; nits/perf
#     are intentionally out of scope — add them later as separate roles).
#   - Enabled agents are round-robin assigned to specializations. With <2 enabled
#     agents, a single agent runs both specializations sequentially.
#   - All findings are returned; no severity filtering (the caller filters).
#   - When input is a file on disk, every finding's <quoted-code> is cross-
#     checked against the real source; mismatches are flagged as
#     quote-valid="false" so you can drop likely hallucinations.
#
# Exit codes:
#   0 — run completed (even if zero findings). Check quote-valid per finding.
#   3 — every dispatched agent failed
#   4 — config error (missing config, no enabled agents, role unknown)
#   5 — usage error (missing input, unknown flag, file not found)
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
source "$SCRIPT_DIR/config.sh"

OUTPUT_FORMAT="markdown"
INPUT_KIND="file"        # file | diff
INPUT_PATH=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --xml)       OUTPUT_FORMAT="xml"; shift ;;
        --diff)      INPUT_KIND="diff"; shift ;;
        -h|--help)   sed -n '2,42p' "$0"; exit $EXIT_OK ;;
        --)          shift; INPUT_PATH="${1:-}"; break ;;
        -*)          echo -e "${RED}Error: unknown flag: $1${NC}" >&2; exit $EXIT_USAGE ;;
        *)           INPUT_PATH="$1"; shift; break ;;
    esac
done

config_validate || exit $EXIT_CONFIG_ERROR

# --- Load input ---
CODE_CONTENT=""
INPUT_SOURCE_LABEL=""
if [[ "$INPUT_KIND" == "diff" ]]; then
    if [[ -t 0 ]]; then
        echo -e "${RED}Error: --diff requires a unified diff on stdin${NC}" >&2
        exit $EXIT_USAGE
    fi
    CODE_CONTENT=$(cat)
    INPUT_SOURCE_LABEL="${INPUT_PATH:-(stdin diff)}"
elif [[ -n "$INPUT_PATH" ]]; then
    if [[ ! -f "$INPUT_PATH" ]]; then
        echo -e "${RED}Error: file not found: $INPUT_PATH${NC}" >&2
        exit $EXIT_USAGE
    fi
    CODE_CONTENT=$(cat "$INPUT_PATH")
    INPUT_SOURCE_LABEL="$INPUT_PATH"
else
    echo -e "${RED}Error: no input (provide a file path or --diff with stdin)${NC}" >&2
    exit $EXIT_USAGE
fi

# --- Determine agents ---
ENABLED_AGENTS=()
while IFS= read -r a; do
    [[ -n "$a" ]] && ENABLED_AGENTS+=("$a")
done < <(config_enabled_agents)

if [[ ${#ENABLED_AGENTS[@]} -eq 0 ]]; then
    echo -e "${RED}Error: no agents enabled in $CONSILIUM_CONFIG${NC}" >&2
    exit $EXIT_CONFIG_ERROR
fi

SPECIALIZATIONS=(security correctness)

# Fixed cost: always exactly len(SPECIALIZATIONS) passes — regardless of how
# many agents are enabled in the config. Extra agents are intentionally ignored
# so adding a 3rd/4th agent does not inflate review cost.
declare -a ASSIGN_AGENTS ASSIGN_ROLES
for i in "${!SPECIALIZATIONS[@]}"; do
    role="${SPECIALIZATIONS[$i]}"
    # Pick the i-th enabled agent if available, otherwise wrap back to the first.
    idx=$(( i < ${#ENABLED_AGENTS[@]} ? i : 0 ))
    ASSIGN_AGENTS+=("${ENABLED_AGENTS[$idx]}")
    ASSIGN_ROLES+=("$role")
done

# --- Resolve backend script for each assigned agent ---
backend_script() {
    case "$1" in
        codex-cli)   echo "$SCRIPT_DIR/codex-query.sh" ;;
        gemini-cli)  echo "$SCRIPT_DIR/gemini-query.sh" ;;
        opencode)    echo "$SCRIPT_DIR/opencode-query.sh" ;;
        claude-code) echo "$SCRIPT_DIR/claude-query.sh" ;;
        *)           echo "" ;;
    esac
}

# --- Build the per-request user prompt ---
# Code content is wrapped in CDATA so quotes, angle brackets, and xml-like
# sequences in user code can't break the outer prompt framing.
make_prompt() {
    local kind="$1"
    local label="$2"
    local content="$3"

    # Line-numbered rendering for file input makes it easier for the agent to
    # pick correct line-start/line-end and quote the matching text.
    local body
    if [[ "$kind" == "file" ]]; then
        body=$(awk '{printf "%4d  %s\n", NR, $0}' <<< "$content")
    else
        body="$content"
    fi

    local escaped_body
    escaped_body="${body//]]>/]]]]><![CDATA[>}"

    cat <<PROMPT
<input kind="${kind}" source="${label}">
<![CDATA[
${escaped_body}
]]>
</input>

<task>
Perform a focused code review on the input above, restricted to your specialization.
Respond with ONE OR MORE <finding> elements in the exact schema below.
If you have no findings in your specialization, respond with a single self-closing <findings/> element and nothing else.
Do NOT add prose, headings, markdown, or XML outside the <finding> elements.
</task>

<schema>
<finding severity="critical|warning|nit" category="security|correctness" file="${label}" line-start="N" line-end="N" confidence="0.0..1.0">
  <title>one-sentence summary</title>
  <rationale><![CDATA[why this is an issue; include ONE reason this might be a false positive]]></rationale>
  <suggested-fix><![CDATA[concrete code or steps]]></suggested-fix>
  <quoted-code><![CDATA[the exact source text spanning lines line-start..line-end, taken verbatim from the input]]></quoted-code>
</finding>
</schema>

<rules>
- Cite real line numbers. quoted-code MUST match the input text at those lines exactly; the caller validates this.
- Confidence MUST reflect genuine uncertainty. A finding you are not sure about belongs at confidence <= 0.6.
- Stay inside your specialization. Do not emit findings from other categories.
- No nits unless they are on the critical path of the specialization.
- Keep rationale under 6 sentences.
- You have read-only access to the surrounding project directory. Use it: Read/Grep/Glob neighboring files, check call sites, look at tests, consult CLAUDE.md / README / config, and verify data flow before asserting a finding. Do not modify anything.
</rules>
PROMPT
}

# --- Dispatch in parallel ---
RESP_DIR=$(mktemp -d)
trap "rm -rf '$RESP_DIR'" EXIT

declare -a PIDS OUT_FILES ERR_FILES KEYS
total=${#ASSIGN_AGENTS[@]}
echo -e "${CYAN}  CODE REVIEW — $total pass(es): ${ASSIGN_AGENTS[*]} / roles=${ASSIGN_ROLES[*]}${NC}" >&2
echo -e "${YELLOW}[Launching parallel specialist queries...]${NC}" >&2

for i in "${!ASSIGN_AGENTS[@]}"; do
    agent="${ASSIGN_AGENTS[$i]}"
    role="${ASSIGN_ROLES[$i]}"
    backend="$(config_get_field "$agent" backend)"
    script="$(backend_script "$backend")"
    key="${agent}.${role}"
    out="$RESP_DIR/${key}.out"
    err="$RESP_DIR/${key}.err"

    if [[ -z "$script" || ! -x "$script" ]]; then
        echo -e "${RED}Skipping '$agent/$role': backend '$backend' unavailable${NC}" >&2
        : > "$out"
        echo "backend unavailable: $backend" > "$err"
        PIDS+=("")
        OUT_FILES+=("$out"); ERR_FILES+=("$err"); KEYS+=("$key")
        continue
    fi

    prompt="$(make_prompt "$INPUT_KIND" "$INPUT_SOURCE_LABEL" "$CODE_CONTENT")"
    (
        CONSILIUM_ROLE_OVERRIDE="$role" \
        CONSILIUM_SKIP_OUTPUT_TEMPLATE=1 \
        "$script" "$prompt" > "$out" 2>"$err"
    ) &
    PIDS+=("$!")
    OUT_FILES+=("$out"); ERR_FILES+=("$err"); KEYS+=("$key")
done

# --- Await ---
declare -a EXITS
failed=0
succeeded=0
for i in "${!PIDS[@]}"; do
    pid="${PIDS[$i]}"
    if [[ -z "$pid" ]]; then
        EXITS+=("$EXIT_CONFIG_ERROR")
        failed=$((failed+1))
        continue
    fi
    code=0
    wait "$pid" || code=$?
    EXITS+=("$code")
    if [[ $code -eq 0 ]]; then
        succeeded=$((succeeded+1))
    else
        failed=$((failed+1))
    fi
done

# --- Summary line to stderr ---
for i in "${!KEYS[@]}"; do
    key="${KEYS[$i]}"
    code="${EXITS[$i]}"
    if [[ $code -eq 0 ]]; then
        echo -e "${GREEN}[${key}] ok${NC}" >&2
    else
        echo -e "${RED}[${key}] failed (exit $code) — see ${ERR_FILES[$i]}${NC}" >&2
    fi
done

# If every pass failed, bail out before the validator chokes on empty input.
if [[ $succeeded -eq 0 ]]; then
    exit $EXIT_ALL_FAILED
fi

# --- Parse + validate + render ---
python3 "$SCRIPT_DIR/code_review_validate.py" \
    --input-kind "$INPUT_KIND" \
    --input-path "$INPUT_SOURCE_LABEL" \
    --output-format "$OUTPUT_FORMAT" \
    "$RESP_DIR"
