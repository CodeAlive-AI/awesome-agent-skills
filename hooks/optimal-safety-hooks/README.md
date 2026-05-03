# bash-guard — a Claude Code PreToolUse:Bash safety hook

A small Go program that sits between Claude Code and your shell, parses every Bash command the agent is about to run with a real shell AST, and decides whether to **allow** it or **ask** you. Never `deny` — see [why](#why-ask-never-deny).

It replaces shlex/regex-based hooks that produced two classes of false positives in production:

- **FP-1 — heredoc with English prose:** `cat > /tmp/x <<'EOF'\nWe use find and rm a lot. Don't break.\nEOF` was blocked because the legacy hook ran shlex over the entire command string, choked on the apostrophe in "Don't", and bailed fail-closed on the word "find" appearing in plain prose.
- **FP-2 — `rm -rf` inside a known-safe directory:** `cd /tmp && rm -rf ci-results && mkdir ci-results` was blocked because the legacy "rm-outside-cwd" rule had no notion of safe-by-construction paths like `/tmp`.

Both are now `allow` by design, with fixtures pinning the behaviour (`testdata/fixtures/find_word_in_heredoc_body.json`, `testdata/fixtures/rm_rf_tmp_subdir.json`).

## What makes it different

**1. Real AST, not regex.** Commands are parsed with [`mvdan.cc/sh/v3`](https://github.com/mvdan/sh) — a production-grade Bash parser used by `shfmt`. Regex and shlex hooks systematically misclassify:

- words inside heredoc bodies
- words inside single-quoted strings
- shell substitutions: `$(...)`, backticks
- pipelines that pipe a string into a shell evaluator (`echo "rm -rf /" | bash`)
- executor wrappers that hide the real command (`sudo rm`, `env FOO=bar rm`, `xargs rm`, `find -delete`, `bash -c "rm ..."`, `eval "rm ..."`, `ssh host "rm ..."`)

bash-guard descends into all of those, classifies every span (`Executed` / `Data` / `HeredocBody` / `InlineCode`), and only inspects spans that actually run.

**2. Span classification beats keyword matching.** A keyword like `rm` inside `<<'EOF'...EOF` is data, not an executed command — bash-guard knows. A keyword inside `echo "..." | bash` is executed code on the right side of the pipe, even though it lexically appears as a string literal — bash-guard knows that too.

**3. Asymmetric fail-open.** Pre-trigger parse failures → `allow` (false negative is a one-off, the user catches it). Post-trigger parse failures (we saw a destructive keyword but couldn't parse) → `ask` (do not silently allow when something dangerous *might* be happening). Documented in §3.6 of [`DESIGN.md`](DESIGN.md).

**4. Safe-paths matrix with carve-outs.** Catastrophic-prefix paths (`/etc/...`, `/usr/...`) and home-protected paths (`$HOME/...`) match unconditionally **except** when the operand is on the explicit safe-paths list. `/tmp/foo` is safe; `/etc/nginx` is not. `$HOME/code/myproject/node_modules` is safe iff `myproject` is in the safe-paths list; `$HOME/.ssh` is never safe.

**5. Trusted-projects allowlist.** Per-repo `.claude/bash-guard.toml` is **not** auto-loaded — that would let any hostile repo whitelist `/etc`. A repo's config is only honoured if its root is listed in the global `~/.claude/hooks/bash-guard/trusted-projects.toml`.

**6. Performance budget.** ~0.16 ms quick-reject for commands without any trigger keyword; <5 ms for full parse + rule evaluation; 0–10 ms end-to-end warm. Rebuilds are explicit (`make build`); no per-invocation `go build` wrapper.

## What it asks about

| Rule | Triggers when |
|---|---|
| **rm** | `rm`, `unlink`, `rmdir`, `shred` targeting paths outside the cwd subtree, catastrophic prefixes (`/etc`, `/usr`, …), `$HOME` (with carve-outs for explicit safe paths), or with `--no-preserve-root` |
| **rm via wrappers** | `sudo rm`, `env FOO=bar rm`, `xargs rm`, `find -delete`, `find -exec rm`, `bash -c "rm ..."`, `eval "rm ..."`, `ssh host "rm ..."`, `chroot newroot rm`, `timeout 5 rm`, `nohup rm`, `time rm`, … |
| **rm via pipe-to-shell** | `echo "rm -rf /" \| bash`, `cat script.sh \| sh`, etc. |
| **supabase** | `supabase db push`, `db reset --linked`, `migration repair`, `--db-url <prod>`; ORM migration verbs (`alembic upgrade`, `manage.py migrate`, `prisma migrate deploy`, `drizzle-kit push`, `knex migrate`, `sequelize db:migrate`, `flyway migrate`, `liquibase update`, `rails db:migrate`, `rake db:migrate`, `typeorm migration:run`, `goose up`) |
| **infra** | `kubectl delete/apply/patch`, destructive `gcloud compute/storage/...`, `helm install/upgrade/uninstall`, `docker rm/system prune`, destructive Mongo (`drop`, `deleteMany`, `mongorestore`, `mongodump`), `terraform/tofu apply/destroy`, `gsutil rm`, `git push -f / --force`, `curl -X DELETE/POST/PUT` against OpenSearch/Elasticsearch URLs |

The rule set is open: a new rule is one Go file implementing the `Rule` interface (`Name() / Triggers() / Check()`), plus ≥3 golden-table fixtures. See [`src/CLAUDE.md`](src/CLAUDE.md) for the maintenance protocol.

What it explicitly does **not** trigger on:

- read-only verbs (`kubectl get`, `gcloud describe`, `helm list`, `docker ps`, `git push` without `-f`)
- `--dry-run` variants of destructive verbs (current behaviour: still asks; see open question in `DESIGN.md`)
- commands inside heredoc bodies, single-quoted strings, or comments

## Why ask, never deny

Claude Code's hook protocol supports three decisions: `allow`, `ask`, `deny`. bash-guard only ever emits the first two — and the `Level` enum in [`src/decision.go`](src/decision.go) enforces this at compile time.

**Reasoning.** A `deny` decision is a hard wall the agent immediately tries to climb over. In practice:

- The agent rephrases the command (`rm -rf` → `find … -delete`).
- It splits the command (`rm dir/* && rmdir dir`).
- It retries through a different wrapper (`sudo rm`, `bash -c 'rm …'`).
- It silently switches to a write-via-Edit equivalent.

`deny` is hostile to the agent's planner without informing the human. `ask` keeps the human in the loop — which is the only durable defence — and gives the agent a clear signal that the destructive intent was recognised. Empirically (and per the consilium review of the design), `ask` reduces both false-negative escapes ("agent worked around the block") and operator fatigue ("why does this keep silently failing?").

This is non-negotiable in this project. Don't add a `LevelDeny` constant.

## Install

Requires Go ≥ 1.21 and `jq` (for safe `settings.json` editing).

```bash
git clone https://github.com/CodeAlive-AI/awesome-agent-skills.git
cd awesome-agent-skills/hooks/optimal-safety-hooks

./install.sh --shadow     # logs every decision, never blocks. Recommended for first install.
./install.sh --dry-run    # same effect as --shadow, with a distinct log label
./install.sh --live       # real enforcement — emits ask for risky commands
./install.sh --uninstall  # remove hook entry + symlink
```

What `install.sh` does, idempotently:

1. Verifies Go is on `PATH`.
2. Symlinks `~/.claude/hooks/bash-guard` → this directory's `src/`.
3. Builds `bash_guard.bin` (warms the Go cache).
4. Patches `~/.claude/settings.json` with a `PreToolUse[matcher=Bash]` entry pointing at the binary. Existing hooks are preserved; previous `bash-guard` entries are replaced. A timestamped backup is written next to the file.

Switching modes later is the same command — `settings.json` is re-read on every hook fire, so no Claude Code restart is needed.

## Recommended workflow

1. **`--shadow` for a week.** Watch `~/.claude/logs/bash-guard.jsonl` (`tail -f … | jq '.'`) and inspect what it *would have* asked about. Each entry has `would_decide`, `rule`, `reason_code`, `command_hash` (set `BASH_GUARD_LOG_COMMANDS=1` to log raw commands; off by default).
2. **Tune safe paths.** If you see ask decisions on legitimate work in your project, add the project root to `~/.claude/hooks/bash-guard/trusted-projects.toml` (see template in repo) and put project-specific safe paths in `<repo>/.claude/bash-guard.toml`.
3. **Switch to `--live`.** Once the noise floor is acceptable.

## Architecture

| File | What lives here |
|---|---|
| `src/main.go` | Pipeline: stdin JSON → quickReject → parse → rule eval → emit JSON. Mode resolution, audit. |
| `src/parser.go` | mvdan/sh AST walk, span classification, lexical-cwd tracking from `cd` statements. |
| `src/unwrap.go` | Executor wrappers: sudo, env, command, builtin, exec, time, nice, nohup, timeout, chroot, ssh, bash/sh -c, eval, xargs, find. |
| `src/safe_paths.go` | realpath + lstat-based path classification with POSIX rm trailing-slash semantics, catastrophic-prefix matrix, $HOME carve-outs. |
| `src/rule_rm.go` | `rm`, `unlink`, `rmdir`, `shred`. |
| `src/rule_supabase.go` | Supabase CLI + ORM migrations. |
| `src/rule_infra.go` | kubectl, gcloud, helm, docker, mongo*, terraform/tofu, gsutil, git push -f, curl-vs-OpenSearch. |
| `src/decision.go` | `Level` enum (Allow / Ask only — no Deny), aggregation: ask wins. |
| `src/audit.go` | JSONL log at `~/.claude/logs/bash-guard.jsonl` with size-based rotation, 0o600 perms. |
| `src/config.go` | TOML loader, trusted-projects allowlist. |
| `testdata/fixtures/*.json` | Golden-table fixtures: `(decision, rule, reason_code)` tuples. ~87 cases. |
| `DESIGN.md` | Full architecture, consilium review, asymmetric fail-open rationale, open questions. |

For non-trivial changes, read `DESIGN.md` first. For day-to-day maintenance, [`src/CLAUDE.md`](src/CLAUDE.md) has the edit/rebuild loop, fixture protocol, and "what NOT to do" list.

## Inspecting behaviour

```bash
# tail the audit log
tail -f ~/.claude/logs/bash-guard.jsonl | jq '.'

# selftest: 4 fixed cases including FP-1 and FP-2 regressions
~/.claude/hooks/bash-guard/bash_guard.bin --selftest

# single-shot dry-fire
echo '{"tool_name":"Bash","tool_input":{"command":"rm -rf /tmp/x"},"cwd":"/tmp"}' \
  | ~/.claude/hooks/bash-guard/bash_guard.bin
```

## License

MIT — same as the parent repo.
