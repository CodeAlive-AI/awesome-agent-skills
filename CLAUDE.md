# Repository conventions for awesome-agent-skills

Instructions for agents working in this repo. Keep them short and enforce them strictly.

## Every skill MUST ship a README.md

Each directory under `skills/<skill-name>/` must contain a `README.md` alongside `SKILL.md`. This is **load-bearing**:

- `SKILL.md` is the agent-facing contract (loaded at runtime by the skills host).
- `README.md` is the human-facing entry point (shown on GitHub when someone opens the skill folder).

They serve different audiences and cannot substitute for each other. PRs that add a new skill without a `README.md`, or that materially change a skill's behavior without refreshing `README.md`, are incomplete.

### When to update `README.md`

Any time you change:

- The set of modes / entry points the skill exposes
- The install command or prerequisites
- The output schema (fields, severity levels, XML element names)
- The research / sources the skill is grounded in
- The file structure under `skills/<skill-name>/`

If a change touches user-visible behavior, the corresponding `README.md` section must be updated in the **same PR**. "I'll update the README later" is not an option.

### Required sections

At minimum, a skill's `README.md` should cover:

1. **Title + one-paragraph pitch** — what it does, for whom, why it's useful
2. **Install** — the exact `npx skills add ...` command
3. **Prerequisites** — external CLIs, API keys, tools the skill depends on
4. **Quick start** — 3-5 copy-pasteable invocations that show the common path
5. **What it does** — the skill's modes / entry points, with a short description of each
6. **Key features** — bullet list of distinguishing design choices (guardrails, research-backed mechanisms, output formats)
7. **Sources and methodology** (when applicable) — papers / standards / prior art the skill builds on. Cite with arXiv IDs or stable URLs, not vague references.
8. **File structure** — an ASCII tree of `skills/<skill-name>/` so readers know what's inside
9. **License** — `MIT` (repo-wide)

Look at existing skills (`skills/ubiquitous-language/README.md`, `skills/semantic-scholar-deep/README.md`, `skills/agents-consilium/README.md`) for the established style before writing a new one.

## Repo-root README

The top-level `README.md` is the index. When adding a new skill, also add a row to the **Skills** table there with:

- Skill name linking to its folder
- One-line description (use the same pitch as the skill's `README.md`)
- Install command

Keep the row concise — details belong in the skill's own `README.md`.

## License

All skills in this repo are MIT-licensed. Do not introduce per-skill license files unless the user explicitly asks.
