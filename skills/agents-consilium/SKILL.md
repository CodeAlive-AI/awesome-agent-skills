---
name: agents-consilium
description: "Orchestrate consultations with external AI agents (OpenAI Codex CLI and Google Gemini CLI) for code reviews, second opinions, investigations, and consensus building. Use when needing a second opinion on architecture or design decisions, requesting code review from another perspective, investigating bugs with fresh eyes, or building consensus on critical decisions by querying multiple agents. Not for simple questions answerable from docs or codebase — use web search or codebase exploration instead."
---

# Consilium: Multi-Agent Orchestration

Query external AI agents for independent, unbiased expert opinions. Each agent has a distinct thinking role and responds in a structured format for easy comparison.

## Design Principles

**Intellectual independence**: Agents are instructed to think from first principles, challenge the framing of questions, and propose alternatives not mentioned in the query. They are free thinkers within the given context, not yes-men.

**Role differentiation**:
- **Codex** = Rigorous Analyst — precision, code correctness, edge cases, implementation depth, security
- **Gemini** = Lateral Thinker — cross-domain patterns, creative alternatives, questioning premises, big picture

**Structured output**: All agents respond using a common template (Assessment, Key Findings, Blind Spots, Alternatives, Recommendation with confidence level), making synthesis straightforward.

## Anti-Bias Protocol

When formulating queries for consilium, follow these rules to maximize the value of independent opinions:

1. **State the problem, not your solution.** Instead of "Should we use X?", describe the constraints and goals.
2. **Don't lead.** Avoid "I think X is best, what do you think?" — this anchors the response.
3. **Include raw context.** Pipe code files or paste error logs directly rather than summarizing them (summaries carry your interpretation).
4. **Omit your hypothesis when possible.** Let agents form their own before revealing yours.

## Read-Only Mode

External agents can read files and analyze code but CANNOT create, edit, or delete anything. Only the primary agent implements changes based on their recommendations.

## Scripts

All scripts in `scripts/` directory. The skill auto-detects its install location.

### Single Agent Queries

```bash
# Codex — Rigorous Analyst (deep, precise, implementation-focused)
scripts/codex-query.sh "question" [context_file]
cat file.py | scripts/codex-query.sh "review this"

# Gemini — Lateral Thinker (broad, creative, premise-challenging)
scripts/gemini-query.sh "question" [context_file]
cat file.py | scripts/gemini-query.sh "review this"
```

### Consensus Query (Both Agents in Parallel)

```bash
scripts/consensus-query.sh "architecture question"
cat file.py | scripts/consensus-query.sh "review this code"
```

## When to Use Which

| Situation | Script | Why |
|-----------|--------|-----|
| Code review, security audit | `codex-query.sh` | Codex excels at code-level precision and edge cases |
| Architecture decision, design choice | `consensus-query.sh` | Need both depth (Codex) and breadth (Gemini) |
| "Are we solving the right problem?" | `gemini-query.sh` | Gemini challenges premises and sees the bigger picture |
| Bug investigation, root cause analysis | `codex-query.sh` | Codex goes deep into implementation details |
| Exploring alternatives, brainstorming | `gemini-query.sh` | Gemini draws cross-domain analogies |
| High-stakes decision (irreversible) | `consensus-query.sh` | Two independent perspectives reduce blind spots |

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

- `CODEX_MODEL`: Override Codex model (default: `gpt-5.4`)
- `GEMINI_MODEL`: Override Gemini model (default: `gemini-3.1-pro-preview`)
- `AGENT_TIMEOUT`: Timeout seconds (default: 1200)

## Prerequisites

- [Codex CLI](https://github.com/openai/codex) installed and authenticated (`codex --version`)
- [Gemini CLI](https://github.com/google-gemini/gemini-cli) installed and authenticated (`gemini --version`)
