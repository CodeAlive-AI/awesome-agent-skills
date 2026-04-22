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

## Contributing

Each skill lives in `skills/<skill-name>/` with a `SKILL.md` at the root. See any existing skill for the structure.

## License

MIT
