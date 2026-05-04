# ⚠️ awesome-agent-skills — ARCHIVED — moved to [CodeAlive-AI/ai-driven-development](https://github.com/CodeAlive-AI/ai-driven-development)

> [!IMPORTANT]
> **This repository has been consolidated into [CodeAlive-AI/ai-driven-development](https://github.com/CodeAlive-AI/ai-driven-development) and is now archived (read-only).**
>
> All 5 skills and the `bash-guard` Bash safety hook now live in the new umbrella collection at https://github.com/CodeAlive-AI/ai-driven-development.

---

## Where the content moved

### Skills

| Old path | New location |
|---|---|
| `skills/agents-consilium/` | [`ai-driven-development/skills/agents-consilium`](https://github.com/CodeAlive-AI/ai-driven-development/tree/main/skills/agents-consilium) |
| `skills/ubiquitous-language/` | [`ai-driven-development/skills/ubiquitous-language`](https://github.com/CodeAlive-AI/ai-driven-development/tree/main/skills/ubiquitous-language) |
| `skills/fetch-url-as-markdown/` | [`ai-driven-development/skills/fetch-url-as-markdown`](https://github.com/CodeAlive-AI/ai-driven-development/tree/main/skills/fetch-url-as-markdown) |
| `skills/semantic-scholar-deep/` | [`ai-driven-development/skills/semantic-scholar-deep`](https://github.com/CodeAlive-AI/ai-driven-development/tree/main/skills/semantic-scholar-deep) |
| `skills/maintaining-macos-health/` | [`ai-driven-development/skills/maintaining-macos-health`](https://github.com/CodeAlive-AI/ai-driven-development/tree/main/skills/maintaining-macos-health) |

### Hooks

| Old path | New location |
|---|---|
| `hooks/optimal-safety-hooks/` (`bash-guard`) | [`ai-driven-development/hooks/balanced-safety-hooks`](https://github.com/CodeAlive-AI/ai-driven-development/tree/main/hooks/balanced-safety-hooks) |

---

## Install (new location)

**Skills:**

```bash
# All 5 of the previously-here skills (plus 13 more in the umbrella collection)
npx skills add CodeAlive-AI/ai-driven-development

# Or pick one
npx skills add CodeAlive-AI/ai-driven-development --skill agents-consilium
```

**Bash safety hook (`bash-guard`):**

```bash
curl -fsSL https://raw.githubusercontent.com/CodeAlive-AI/ai-driven-development/main/hooks/balanced-safety-hooks/install-prebuilt.sh | sh
```

**Claude Code plugin install:**

```bash
/plugin marketplace add CodeAlive-AI/ai-driven-development
/plugin install ai-driven-development@ai-driven-development
```

---

## What about the existing `bash-guard-v0.1.0` release?

The original [`bash-guard-v0.1.0`](https://github.com/CodeAlive-AI/awesome-agent-skills/releases/tag/bash-guard-v0.1.0) release in this repo remains accessible — its binaries are unchanged and continue to work for users who already pinned to it. New installs should use the [republished release](https://github.com/CodeAlive-AI/ai-driven-development/releases/tag/bash-guard-v0.1.0) under `ai-driven-development`, which is what `install-prebuilt.sh` now points to.

---

## Why?

We consolidated 8 separate skill/protocol repos into a single umbrella collection that follows the [Agent Skills](https://agentskills.io) open standard, so skills work seamlessly across Claude Code, Codex CLI, OpenCode, Cursor, Gemini CLI, Antigravity, and any agent supporting `npx skills add`. See [the new repo's README](https://github.com/CodeAlive-AI/ai-driven-development#readme) for the full collection (18 skills + 1 hook).

---

## Archive notice

This repo is **archived and read-only**. Issues, PRs, and discussions should be filed against [`CodeAlive-AI/ai-driven-development`](https://github.com/CodeAlive-AI/ai-driven-development).

The original source files remain in this archive for git history reference.

## License

MIT
