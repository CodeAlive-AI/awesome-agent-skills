# awesome-agent-skills

A curated collection of useful, general-purpose skills for AI coding agents. Many of these we actively use ourselves at [CodeAlive](https://codealive.ai) in our daily work.

These skills are **not tied to CodeAlive** — they work with any agent that supports the [skills](https://skills.sh) standard: Claude Code, Cursor, Codex, Gemini CLI, and [40+ others](https://skills.sh).

> Looking for CodeAlive-specific skills (semantic code search, codebase Q&A)? Those live in a separate repo: **[CodeAlive-AI/codealive-skills](https://github.com/CodeAlive-AI/codealive-skills)**.

## Skills

| Skill | Description | Install |
|-------|-------------|---------|
| [agents-consilium](skills/agents-consilium/) | Multi-agent orchestration — query Codex, Claude Code, OpenCode, Gemini in parallel. Different models bring **different angles**: more original ideas in brainstorming & feature design, and broader coverage in code review (each model spots a different scope of issues) | `npx skills add CodeAlive-AI/awesome-agent-skills@agents-consilium -g -y` |
| [ubiquitous-language](skills/ubiquitous-language/) | Domain thesaurus manager — DDD naming consistency, thesaurus generation, naming audit | `npx skills add CodeAlive-AI/awesome-agent-skills@ubiquitous-language -g -y` |
| [semantic-scholar-deep](skills/semantic-scholar-deep/) | Deep research over the Semantic Scholar Graph API — backward references, recommendations, batch lookup (up to 500 IDs), multi-hop citation-graph BFS, snippet search. Ships with an optional paired subagent for token-isolated literature reviews | `npx skills add CodeAlive-AI/awesome-agent-skills@semantic-scholar-deep -g -y` |
| [fetch-url-as-markdown](skills/fetch-url-as-markdown/) | URL → clean Markdown via local trafilatura (real-browser UA, anti-stub guards, structured exit codes), with Exa MCP as a fallback for JS-rendered or anti-bot pages. Drop-in replacement for the built-in WebFetch | `npx skills add CodeAlive-AI/awesome-agent-skills@fetch-url-as-markdown -g -y` |
| [maintaining-macos-health](skills/maintaining-macos-health/) | macOS disk cleanup + dev-machine optimization + proactive health alerting. Triage flow for kernel panic / watchdog timeout / `vm-compressor-space-shortage` / Jetsam events. Tiered cleanup playbook (zero-risk → discuss-first), Mole-style safety guards, and a noise-resistant LaunchAgent alerter (3 CRITICAL-only triggers, hysteresis, calibration window). Apple Silicon Mac focus | `npx skills add CodeAlive-AI/awesome-agent-skills@maintaining-macos-health -g -y` |

## Hooks

Standalone agent-safety hooks that don't fit the skills standard — typically because they have to live inside Claude Code's hook protocol or run as compiled binaries.

| Hook | Description | Install |
|------|-------------|---------|
| [optimal-safety-hooks](hooks/optimal-safety-hooks/) | `bash-guard` — Claude Code `PreToolUse:Bash` safety hook in Go. AST-based parsing (heredocs, quotes, `sudo`/`env`/`xargs`/`bash -c`/`eval`/`ssh`/pipe-to-shell), catastrophic-path matrix with carve-outs. Default rule set uses `ask` (not `deny`) so agents don't paper over the block. Covers `rm`/`unlink`/`shred`, ORM migrations, infra (kubectl/gcloud/helm/docker/terraform/`git push -f`), PaaS CLIs (railway/fly/heroku/…), DB clients (psql/redis-cli), and cloud control-plane API mutations | `curl -fsSL https://raw.githubusercontent.com/CodeAlive-AI/awesome-agent-skills/main/hooks/optimal-safety-hooks/install-prebuilt.sh \| sh` |

### bash-guard

A safety hook that intercepts every Bash command Claude Code is about to run, parses it with a real shell AST ([`mvdan.cc/sh`](https://github.com/mvdan/sh)), and asks for human confirmation only on the genuinely destructive ones (`rm` outside cwd, `kubectl delete`, `terraform destroy`, `psql -c "DROP DATABASE"`, `curl -X POST` to a Railway `volumeDelete` mutation, …). Designed for low false-positive rate so you actually read the prompts instead of mashing Allow.

**Install (no Go required):**

```bash
curl -fsSL https://raw.githubusercontent.com/CodeAlive-AI/awesome-agent-skills/main/hooks/optimal-safety-hooks/install-prebuilt.sh | sh
```

Detects OS/arch (darwin / linux × arm64 / amd64), downloads the prebuilt binary from the latest GitHub release, verifies its SHA-256, and patches `~/.claude/settings.json`.

Full docs, design rationale, and the full rule list: **[hooks/optimal-safety-hooks/README.md](hooks/optimal-safety-hooks/)**.

## Contributing

Each skill lives in `skills/<skill-name>/` with a `SKILL.md` at the root. See any existing skill for the structure.

Each hook lives in `hooks/<hook-name>/` with its own `README.md` and install script.

## License

MIT
