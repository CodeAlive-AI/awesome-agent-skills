#!/bin/bash
#
# Consensus Query — opinions from every enabled agent in config.json, in parallel.
#
# Usage:
#   consensus-query.sh "question"
#   consensus-query.sh --xml "question"
#   cat file.ts | consensus-query.sh "review this code"
#   consensus-query.sh --list-agents        # dump plan as XML, no queries
#   consensus-query.sh --help
#
# Options:
#   --xml            Emit responses as <consilium-report> XML (stable for agent consumers).
#                    Default is a human-readable markdown report.
#   --list-agents    Print the current plan (all configured agents, enabled/disabled,
#                    with model/role/backend-available) as XML and exit 0.
#   -h, --help       Show this help.
#
# Exit codes:
#   0 — all queried agents succeeded (or --list-agents completed)
#   2 — partial failure (at least one agent succeeded, at least one failed)
#   3 — every queried agent failed
#   4 — config error (missing config, no enabled agents, unknown backend)
#   5 — usage error (missing prompt, unknown flag)
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
source "$SCRIPT_DIR/config.sh"

OUTPUT_FORMAT="markdown"  # markdown | xml
LIST_ONLY=false
PROMPT=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --xml)          OUTPUT_FORMAT="xml"; shift ;;
        --list-agents)  LIST_ONLY=true; shift ;;
        -h|--help)      sed -n '2,26p' "$0"; exit $EXIT_OK ;;
        --)             shift; PROMPT="${1:-}"; break ;;
        -*)             echo -e "${RED}Error: unknown flag: $1${NC}" >&2; exit $EXIT_USAGE ;;
        *)              PROMPT="$1"; shift; break ;;
    esac
done

config_validate || exit $EXIT_CONFIG_ERROR

# --list-agents: emit plan and exit.
if $LIST_ONLY; then
    config_xml_plan
    exit $EXIT_OK
fi

if [[ -z "$PROMPT" ]]; then
    echo -e "${RED}Error: No prompt provided${NC}" >&2
    echo "Usage: $0 [--xml] \"question\"" >&2
    exit $EXIT_USAGE
fi

# Resolve the query script path for a given agent backend.
backend_script() {
    case "$1" in
        codex-cli)   echo "$SCRIPT_DIR/codex-query.sh" ;;
        gemini-cli)  echo "$SCRIPT_DIR/gemini-query.sh" ;;
        opencode)    echo "$SCRIPT_DIR/opencode-query.sh" ;;
        claude-code) echo "$SCRIPT_DIR/claude-query.sh" ;;
        *)           echo "" ;;
    esac
}

ENABLED_AGENTS=()
while IFS= read -r a; do
    [[ -n "$a" ]] && ENABLED_AGENTS+=("$a")
done < <(config_enabled_agents)

ALL_AGENTS=()
while IFS= read -r a; do
    [[ -n "$a" ]] && ALL_AGENTS+=("$a")
done < <(config_all_agents)

if [[ ${#ENABLED_AGENTS[@]} -eq 0 ]]; then
    echo -e "${RED}Error: no agents enabled in $CONSILIUM_CONFIG${NC}" >&2
    exit $EXIT_CONFIG_ERROR
fi

# Capture piped input if any.
STDIN_CONTENT=""
if [[ ! -t 0 ]]; then
    STDIN_CONTENT=$(cat)
fi

echo -e "${CYAN}  CONSENSUS QUERY — ${#ENABLED_AGENTS[@]} agent(s) in parallel: ${ENABLED_AGENTS[*]}${NC}" >&2
echo -e "${YELLOW}[Launching parallel queries...]${NC}" >&2

declare -a AGENT_IDS PIDS OUT_FILES ERR_FILES LABELS MODELS ROLES BACKENDS STATUSES EXITS

for agent in "${ENABLED_AGENTS[@]}"; do
    backend="$(config_get_field "$agent" backend)"
    script="$(backend_script "$backend")"
    label="$(config_get_field "$agent" label)"; label="${label:-$agent}"
    model="$(config_get_field "$agent" model)"
    role="$(config_get_field "$agent" role)"

    AGENT_IDS+=("$agent")
    LABELS+=("$label")
    MODELS+=("$model")
    ROLES+=("$role")
    BACKENDS+=("$backend")

    if [[ -z "$script" || ! -x "$script" ]]; then
        echo -e "${RED}Skipping '$agent': unknown/unavailable backend '$backend'${NC}" >&2
        STATUSES+=("skipped")
        EXITS+=("$EXIT_CONFIG_ERROR")
        OUT_FILES+=("")
        ERR_FILES+=("")
        PIDS+=("")
        continue
    fi

    out=$(mktemp)
    err=$(mktemp)
    if [[ -n "$STDIN_CONTENT" ]]; then
        echo "$STDIN_CONTENT" | "$script" "$PROMPT" > "$out" 2>"$err" &
    else
        "$script" "$PROMPT" > "$out" 2>"$err" &
    fi

    STATUSES+=("pending")
    EXITS+=("0")
    OUT_FILES+=("$out")
    ERR_FILES+=("$err")
    PIDS+=("$!")
done

cleanup() {
    for f in "${OUT_FILES[@]:-}" "${ERR_FILES[@]:-}"; do
        [[ -n "$f" ]] && rm -f "$f"
    done
}
trap cleanup EXIT

# Wait for all dispatched agents and record exit codes.
for i in "${!AGENT_IDS[@]}"; do
    [[ "${STATUSES[$i]}" == "skipped" ]] && continue
    pid="${PIDS[$i]}"
    [[ -z "$pid" ]] && continue
    code=0
    wait "$pid" || code=$?
    EXITS[$i]="$code"
    if [[ $code -eq 0 ]]; then
        STATUSES[$i]="ok"
    else
        STATUSES[$i]="failed"
    fi
done

# Count outcomes (queried agents only).
queried=0
succeeded=0
failed=0
for i in "${!AGENT_IDS[@]}"; do
    case "${STATUSES[$i]}" in
        ok)      queried=$((queried+1)); succeeded=$((succeeded+1)) ;;
        failed)  queried=$((queried+1)); failed=$((failed+1)) ;;
        skipped) queried=$((queried+1)); failed=$((failed+1)) ;;
    esac
done

# -------- Render report --------
if [[ "$OUTPUT_FORMAT" == "xml" ]]; then
    echo "<consilium-report prompt-length=\"${#PROMPT}\">"
    # Queried agents (enabled).
    for i in "${!AGENT_IDS[@]}"; do
        agent="${AGENT_IDS[$i]}"
        label="${LABELS[$i]}"
        model="${MODELS[$i]}"
        role="${ROLES[$i]}"
        backend="${BACKENDS[$i]}"
        status="${STATUSES[$i]}"
        code="${EXITS[$i]}"
        printf '  <agent id="%s" label="%s" backend="%s" model="%s" role="%s" status="%s" exit-code="%s">\n' \
            "$(printf '%s' "$agent"   | xml_escape)" \
            "$(printf '%s' "$label"   | xml_escape)" \
            "$(printf '%s' "$backend" | xml_escape)" \
            "$(printf '%s' "$model"   | xml_escape)" \
            "$(printf '%s' "$role"    | xml_escape)" \
            "$status" "$code"
        case "$status" in
            ok)
                printf '    <response>'
                cat "${OUT_FILES[$i]}" | cdata_wrap
                printf '</response>\n'
                ;;
            failed)
                printf '    <error>'
                cat "${ERR_FILES[$i]}" | cdata_wrap
                printf '</error>\n'
                ;;
            skipped)
                printf '    <error>Backend %s unavailable</error>\n' \
                    "$(printf '%s' "$backend" | xml_escape)"
                ;;
        esac
        echo "  </agent>"
    done
    # Disabled agents, for agent-consumer introspection.
    for agent in "${ALL_AGENTS[@]}"; do
        in_enabled=false
        for a in "${ENABLED_AGENTS[@]}"; do
            [[ "$a" == "$agent" ]] && in_enabled=true && break
        done
        $in_enabled && continue
        label="$(config_get_field "$agent" label)"; label="${label:-$agent}"
        model="$(config_get_field "$agent" model)"
        role="$(config_get_field "$agent" role)"
        backend="$(config_get_field "$agent" backend)"
        printf '  <agent id="%s" label="%s" backend="%s" model="%s" role="%s" status="disabled"/>\n' \
            "$(printf '%s' "$agent"   | xml_escape)" \
            "$(printf '%s' "$label"   | xml_escape)" \
            "$(printf '%s' "$backend" | xml_escape)" \
            "$(printf '%s' "$model"   | xml_escape)" \
            "$(printf '%s' "$role"    | xml_escape)"
    done
    echo "</consilium-report>"
else
    for i in "${!AGENT_IDS[@]}"; do
        label="${LABELS[$i]}"
        model="${MODELS[$i]}"
        status="${STATUSES[$i]}"
        code="${EXITS[$i]}"
        echo ""
        echo "## ${label} Response (${model})"
        echo ""
        case "$status" in
            ok)      cat "${OUT_FILES[$i]}" ;;
            failed)  echo "[${label} query failed with exit code $code]"; cat "${ERR_FILES[$i]}" ;;
            skipped) echo "[${label} skipped: backend unavailable]" ;;
        esac
    done
    # Disabled block.
    disabled_any=false
    for agent in "${ALL_AGENTS[@]}"; do
        in_enabled=false
        for a in "${ENABLED_AGENTS[@]}"; do
            [[ "$a" == "$agent" ]] && in_enabled=true && break
        done
        $in_enabled && continue
        $disabled_any || { echo ""; echo "## Disabled agents"; echo ""; disabled_any=true; }
        label="$(config_get_field "$agent" label)"; label="${label:-$agent}"
        model="$(config_get_field "$agent" model)"
        echo "- ${label} (${model}) — disabled in config"
    done
    echo ""
    echo "---"
    echo "END OF CONSENSUS REPORT"
fi

# -------- Exit code --------
if [[ $succeeded -eq $queried ]]; then
    exit $EXIT_OK
elif [[ $succeeded -eq 0 ]]; then
    exit $EXIT_ALL_FAILED
else
    exit $EXIT_PARTIAL
fi
