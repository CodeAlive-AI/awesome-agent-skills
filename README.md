# awesome-agent-skills

A collection of general-purpose skills for AI coding agents. Works with any agent that supports the [skills](https://skills.sh) standard: Claude Code, Cursor, Codex, Gemini CLI, and [40+ others](https://skills.sh).

## Skills

| Skill | Description | Install |
|-------|-------------|---------|
| [agents-consilium](skills/agents-consilium/) | Multi-agent orchestration — query Codex CLI and Gemini CLI for independent expert opinions | `npx skills add CodeAlive-AI/awesome-agent-skills@agents-consilium -g -y` |

## Adding new skills

Each skill lives in `skills/<skill-name>/` with a `SKILL.md` at the root. See any existing skill for the structure.

## License

MIT
