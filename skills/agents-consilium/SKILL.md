---
name: agents-consilium
description: "Query external AI agents (Codex, Gemini, OpenCode, Claude Code headless) in parallel for independent second opinions, code review, bug investigation, and consensus on high-stakes decisions. Agents and models are configurable in config.json. Use for architecture choices, security review, or ambiguous problems where independent perspectives matter. Not for simple questions answerable from docs or the codebase — use web search or repo exploration instead."
---

# Consilium: Multi-Agent Orchestration

Query external AI agents for independent, unbiased expert opinions. Each agent has a distinct thinking role and responds in a structured format for easy comparison.

## Contents

- [Quick Start](#quick-start)
- [Design Principles](#design-principles)
- [Anti-Bias Protocol](#anti-bias-protocol)
- [Read-Only Mode](#read-only-mode)
- [Configuration](#configuration)
  - [OpenCode provider choice: Zen vs Google direct](#opencode-provider-choice-zen-vs-google-direct)
  - [Claude Code backend](#claude-code-backend)
- [Scripts](#scripts)
  - [Flags & Exit Codes](#flags--exit-codes)
- [Code Review Mode](#code-review-mode)
- [When to Use Which](#when-to-use-which)
- [Synthesizing Responses](#synthesizing-responses)
- [Prompt Patterns](#prompt-patterns)
- [Environment Variables](#environment-variables)
- [Prerequisites](#prerequisites)

## Quick Start

```bash
# 1. See what's configured (XML plan — dry-run, no agents run).
scripts/consensus-query.sh --list-agents

# 2. Ask the consensus (human-readable markdown).
scripts/consensus-query.sh "Should we use Postgres or SQLite for this CLI tool?"

# 3. Agent-friendly output (stable XML, escaped via CDATA).
scripts/consensus-query.sh --xml "Review this function" < src/auth.py

# 4. Code review mode (2 specialists, quoted-code validated, XML or markdown).
scripts/code-review.sh path/to/file.py
git diff HEAD | scripts/code-review.sh --xml --diff
```

Edit `config.json` to enable/disable agents or swap models. See `config.example.json` for a fuller template with multiple backends.

## Design Principles

**Intellectual independence**: Agents are instructed to think from first principles, challenge the framing of questions, and propose alternatives not mentioned in the query. They are free thinkers within the given context, not yes-men.

**Role differentiation** (set per agent in `config.json`):
- **analyst** = Rigorous Analyst — precision, code correctness, edge cases, implementation depth, security (default for Codex)
- **lateral** = Lateral Thinker — cross-domain patterns, creative alternatives, questioning premises, big picture (default for Gemini / OpenCode with Gemini-3.1-Pro)

**Structured output**: All agents respond using a common template (Assessment, Key Findings, Blind Spots, Alternatives, Recommendation with confidence level), making synthesis straightforward.

## Anti-Bias Protocol

When formulating queries for consilium, follow these rules to maximize the value of independent opinions:

1. **State the problem, not your solution.** Instead of "Should we use X?", describe the constraints and goals.
2. **Don't lead.** Avoid "I think X is best, what do you think?" — this anchors the response.
3. **Include raw context.** Pipe code files or paste error logs directly rather than summarizing them (summaries carry your interpretation).
4. **Omit your hypothesis when possible.** Let agents form their own before revealing yours.

## Agent Freedom and Read-Only Guardrails

Agents are spawned **in the caller's current working directory** with their native agentic toolchain intact. They can:

- `Read`, `Grep`, `Glob`, `find_references`, `git log/blame` across the real repository
- Consult `CLAUDE.md`, `AGENTS.md`, `README`, config files, tests, call sites, neighboring modules
- Use web search / fetch if their backend supports it (Claude Code, OpenCode, Codex all do)
- Run SAST-style introspection via their built-in shells

What they **cannot** do (enforced per backend):

| Backend | Read-only guard |
|---------|-----------------|
| Codex | `--sandbox read-only --ask-for-approval never` |
| Claude Code | `--permission-mode plan` |
| OpenCode | `--agent plan` (plan is opencode's built-in read-only agent) |
| Gemini CLI | `--approval-mode plan` |

No `Edit`, `Write`, `Bash(git commit ...)`, `Bash(rm ...)`, or any write-back tool is authorized. Implementation of recommendations is the caller's job. If a backend tries to escalate (e.g. needs to run a command that violates read-only), the call fails rather than silently escalating.

## Configuration

Agents are declared in `config.json` at the skill root. Each agent has:

| Field | Purpose |
|-------|---------|
| `enabled` | Whether it participates in `consensus-query` |
| `backend` | CLI that actually runs: `codex-cli`, `gemini-cli`, `opencode`, `claude-code` |
| `model` | Model id passed to that CLI |
| `role` | `analyst` (deep/precise) or `lateral` (broad/creative) |
| `label` | Display name in reports (optional) |
| `effort` | **opencode only:** provider-specific reasoning effort — `high` (default), `max`, `minimal`, or any other variant the provider exposes. Maps to `opencode run --variant`. |

Default config (`config.json`):
- `codex` (backend=codex-cli, model=gpt-5.4, role=analyst) — **enabled**
- `gemini-cli` (backend=gemini-cli, model=gemini-3.1-pro-preview, role=lateral) — **disabled**
- `opencode` (backend=opencode, model=opencode/gemini-3.1-pro, role=lateral) — **enabled**
- `claude-code` (backend=claude-code, model=opus, role=analyst) — **disabled**

Edit `config.json` to flip agents on/off or change models. Set `CONSILIUM_CONFIG=/path/to/custom.json` to use an override file.

### OpenCode provider choice: Zen vs Google direct

The `opencode` backend works with any provider/model that OpenCode supports. For Gemini 3.1 Pro you have two options:

- **Zen** (default): `"model": "opencode/gemini-3.1-pro"` — goes through OpenCode Zen. Works out of the box once `opencode providers login opencode` (or a valid Zen credential) is configured.
- **Google direct**: `"model": "google/gemini-3.1-pro-preview"` — goes straight to Google's v1beta API. Requires `GOOGLE_GENERATIVE_AI_API_KEY` (OpenCode does **not** pick up `GEMINI_API_KEY` for this provider).

Flip between them by editing the `model` field; the rest of the config stays the same.

### Claude Code backend

The `claude-code` backend shells out to `claude -p` (headless mode, see [docs](https://code.claude.com/docs/en/headless)). Useful when you want a second Claude in the consilium — e.g. Opus as analyst cross-checking Codex.

- `model`: a shortname (`opus`, `sonnet`, `haiku`) or full id (`claude-opus-4-7`, `claude-sonnet-4-6`).
- Runs in the caller's CWD with `--permission-mode plan` — Claude can freely `Read`/`Grep`/`Glob`/`Bash` read-only across the project, but cannot `Edit`/`Write`. Override with `CLAUDE_PERMISSION_MODE` only if you know what you're doing.
- Authentication uses the same Claude Code credentials the CLI is already logged in with (`claude /login`).

Note: `claude-code` is disabled in the default config to avoid spawning another Claude session accidentally. Flip `enabled` to `true` in `config.json` (or `CONSILIUM_CONFIG`) when you want it in the consensus run.

## Scripts

All scripts in `scripts/` directory. The skill auto-detects its install location.

### Single Agent Queries

Each per-agent script is a no-op (exit 0) when its agent id is `enabled=false` in config, so scripts are safe to call unconditionally.

```bash
# Codex (analyst by default)
scripts/codex-query.sh "question" [context_file]
cat file.py | scripts/codex-query.sh "review this"

# Gemini CLI (lateral by default; disabled in default config)
scripts/gemini-query.sh "question" [context_file]
cat file.py | scripts/gemini-query.sh "review this"

# OpenCode (lateral by default, model per config.json)
scripts/opencode-query.sh "question" [context_file]
cat file.py | scripts/opencode-query.sh "review this"

# Claude Code (analyst by default; disabled in default config)
scripts/claude-query.sh "question" [context_file]
cat file.py | scripts/claude-query.sh "review this"
```

### Consensus Query (All Enabled Agents in Parallel)

```bash
scripts/consensus-query.sh "architecture question"
cat file.py | scripts/consensus-query.sh "review this code"
scripts/consensus-query.sh --xml "review this"            # XML report for agent consumers
scripts/consensus-query.sh --list-agents                   # dry-run: dump plan, don't query
```

`consensus-query.sh` reads `config.json`, launches every agent with `enabled=true` in parallel, and prints their responses grouped by label. Add/remove agents purely by editing the config.

### Flags & Exit Codes

All scripts accept `-h` / `--help`. `consensus-query.sh` also accepts:

| Flag | Effect |
|------|--------|
| `--xml` | Emit `<consilium-report>` with each agent wrapped in `<agent>…<response><![CDATA[…]]></response></agent>`. Stable for agent consumers (no markdown-heading collision). |
| `--list-agents` | Print `<consilium-plan>` (every configured agent, enabled/disabled, with `backend-available`) and exit. No queries are run — use this as an inspection / dry-run. |

Exit codes (stable across all scripts):

| Code | Meaning |
|------|---------|
| `0` | Success, or agent disabled/skipped cleanly |
| `2` | **Consensus only:** partial failure (≥1 succeeded, ≥1 failed) |
| `3` | **Consensus only:** every queried agent failed |
| `4` | Config error (missing CLI, invalid config, unknown role/agent id) |
| `5` | Usage error (missing prompt, unknown flag) |
| other | Propagated from the backend CLI (e.g. `124` on timeout) |

## Code Review Mode

`scripts/code-review.sh` is a focused pipeline for reviewing a single file or a unified diff. It runs **exactly two specialist passes** — `security` and `correctness` — in parallel, then validates each finding's `quoted-code` against the real source.

Design choices are grounded in the 2024-2026 multi-agent code review literature:

- **Two specializations only** (security + correctness). Readability/perf agents empirically produce nit spam and hurt precision.
- **No coordinator / no debate.** The caller (you) adjudicates. Debate rounds empirically entrench errors (Wu et al. 2025; Choi et al. 2025).
- **Heterogeneous models** via the existing config (Codex + OpenCode by default) reduce shared blind spots.
- **Fixed cost.** Adding a 3rd enabled agent does not add a 3rd pass; the skill always runs 2 passes and rotates agents round-robin.
- **Hallucinated line numbers are caught locally.** Every finding carries `<quoted-code>`, and the validator cross-checks it against the source file (`quote-valid="true|false"`).

### Usage

```bash
# File on disk (quoted-code validated against the file)
scripts/code-review.sh path/to/file.py
scripts/code-review.sh --xml path/to/file.py

# Unified diff piped on stdin (quoted-code validation is skipped)
git diff HEAD | scripts/code-review.sh --diff
git diff HEAD | scripts/code-review.sh --xml --diff
```

### Finding schema (XML output)

```xml
<finding index="N" severity="critical|warning|nit" category="security|correctness"
         file="..." line-start="N" line-end="N" confidence="0.0..1.0"
         source-agent="..." source-role="security|correctness"
         quote-valid="true|false">
  <title>...</title>
  <rationale><![CDATA[includes one reason this might be a false positive]]></rationale>
  <suggested-fix><![CDATA[...]]></suggested-fix>
  <quoted-code><![CDATA[verbatim source at line-start..line-end]]></quoted-code>
</finding>
```

Findings are sorted `severity desc, confidence desc`. No severity filtering by default — triage is the caller's job.

### When NOT to use code-review mode

- **Open-ended architecture questions** → use `consensus-query.sh`; specialists will be too narrow.
- **Huge files (>1000 lines)** → split into function-sized diffs first; LLMs degrade past that length.
- **Multi-file cross-references** → not modelled here; rerun per file and stitch findings.

## When to Use Which

Pick by role, not by vendor. The default config has Codex (`analyst`) + OpenCode/Gemini-3.1-Pro (`lateral`) enabled; flip `claude-code` or `gemini-cli` on in `config.json` when you want an additional voice.

| Situation | Script | Role(s) involved |
|-----------|--------|-------------------|
| Code review, security audit | per-agent `analyst` script (`codex-query.sh` or `claude-query.sh`) | analyst — precision, edge cases |
| Architecture decision, design choice | `consensus-query.sh` | analyst + lateral — depth + breadth |
| "Are we solving the right problem?" | per-agent `lateral` script (`opencode-query.sh` or `gemini-query.sh`) | lateral — challenges premises |
| Bug investigation, root cause analysis | per-agent `analyst` script | analyst — goes deep into implementation |
| Exploring alternatives, brainstorming | per-agent `lateral` script | lateral — cross-domain analogies |
| High-stakes or irreversible decision | `consensus-query.sh` | all enabled — reduce blind spots |
| Agent-to-agent integration (downstream parser) | `consensus-query.sh --xml` | any — stable structured output |

## Synthesizing Responses

Agents respond with a shared structure. Compare section by section:

- **Assessment vs Assessment**: Do they frame the problem differently? A framing difference often reveals the most insight.
- **Blind Spots**: Union of both agents' blind spots is your risk map.
- **Alternatives**: Check if either agent proposed something neither you nor the other agent considered.
- **Recommendations**: Agreement = high confidence. Divergence = investigate the reasoning, not just the conclusion.

### Response Patterns

When comparing the two responses, classify the pattern and act accordingly:

- **Agreement**: Both recommend same approach — high confidence, proceed
- **Complementary**: Different valid points that don't conflict — combine insights into a richer picture
- **Contradiction**: Conflicting recommendations — present both with reasoning, let user decide
- **Unique insight**: One agent caught something the other missed — highlight it, this is often the most valuable output

## Prompt Patterns

### Architecture Decision (unbiased framing)
```bash
scripts/consensus-query.sh "We need real-time updates for ~100 concurrent users.
Updates are server-initiated only. Current stack: [describe your stack].
Latency target: under 500ms from event to UI update.
What approach would you recommend and why?"
```

### Code Review (pipe raw code, let agents form opinions)
```bash
cat src/services/auth.py | scripts/codex-query.sh \
  "Review this authentication service. Focus on whatever concerns you most."
```

### Problem Investigation (provide facts, not hypotheses)
```bash
scripts/codex-query.sh "Database query returns empty result.
Direct query with same filter returns 5 documents.
[paste query here]
What's happening?"
```

## Environment Variables

- `CONSILIUM_CONFIG`: Path to a custom JSON config (default: `<skill>/config.json`)
- `CODEX_MODEL`: Override Codex model at runtime (default: value from config)
- `GEMINI_MODEL`: Override Gemini CLI model at runtime (default: value from config)
- `OPENCODE_MODEL`: Override OpenCode model at runtime (default: value from config)
- `OPENCODE_AGENT`: Override OpenCode built-in agent (default: `plan`, read-only)
- `OPENCODE_EFFORT`: Override OpenCode reasoning effort (default: config `effort` field, or `high`)
- `CLAUDE_MODEL`: Override Claude Code model at runtime (alias like `opus` or full id)
- `CLAUDE_PERMISSION_MODE`: Override Claude Code permission mode (default: `plan`)
- `GEMINI_API_KEY`: Required for the `gemini-cli` backend (v1beta model access)
- `GOOGLE_GENERATIVE_AI_API_KEY`: Required if the `opencode` backend uses `google/...` models
- `AGENT_TIMEOUT`: Timeout seconds (default: 1200)

## Prerequisites

- [Codex CLI](https://github.com/openai/codex) installed and authenticated (`codex --version`) — for the `codex-cli` backend
- [OpenCode CLI](https://opencode.ai) installed (`opencode --version`) — for the `opencode` backend. For Zen models (`opencode/...`) run `opencode providers login opencode` once; for Google direct models (`google/...`) set `GOOGLE_GENERATIVE_AI_API_KEY`.
- [Gemini CLI](https://github.com/google-gemini/gemini-cli) installed (`gemini --version`) — for the `gemini-cli` backend (optional; falls back to direct API)
- [Claude Code CLI](https://docs.claude.com/claude-code) installed and logged in (`claude --version`, `claude /login`) — for the `claude-code` backend
- `GEMINI_API_KEY` environment variable — required only when `gemini-cli` backend is enabled (get key at https://ai.google.dev/gemini-api/docs/api-key)
- Python 3 (for config parsing and Gemini API fallback)
