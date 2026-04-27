# Never-touch list

Categories that **must not be deleted** even if the user asks, even with sudo, even when desperate for space. Pushback expected: explain the consequence, suggest an alternative.

## Table of contents

- [Hard-protected paths (system roots)](#hard-protected-paths-system-roots)
- [Sudo allowlist](#sudo-allowlist-the-only-exceptions-inside-private)
- [Hard-protected app bundle categories](#hard-protected-app-bundle-categories)
- [User content paths](#user-content-paths-never-auto-clean)
- [Per-app subfolders that LOOK like cache but contain state](#per-app-subfolders-that-look-like-cache-but-contain-state)
- [OS-level operations that NEVER apply](#os-level-operations-that-never-apply)
- [How to handle pushback](#how-to-handle-pushback)

Lists are derived from Mole's `app_protection.sh` (community-vetted) plus additions from real incidents.

---

## Hard-protected paths (system roots)

Never delete inside these prefixes — even one wrong path can brick the OS. macOS SIP usually blocks these, but a sudo'd `rm -rf` can still cause damage to the writable parts.

```
/
/System
/bin
/sbin
/usr
/etc
/var
/private
/Library/Extensions
```

### Sudo allowlist (the only exceptions inside `/private/...`)

These specific subpaths are safe under sudo, with a `find -mtime` filter:

```
/private/tmp
/private/var/tmp
/private/var/log
/private/var/folders         # Per-user temp; only $TMPDIR subset
/private/var/db/diagnostics
/private/var/db/DiagnosticPipeline
/private/var/db/powerlog
/private/var/db/reportmemoryexception
```

Anything else under `/private/var/db` (especially `uuidtext`, `receipts`, `BootCaches`, `mds`, `mds_stores`) — leave alone. `uuidtext` is the CrashReporter symbol cache; deleting it breaks symbolication of any future crash.

---

## Hard-protected app bundle categories

These bundle ID prefixes are never auto-cleaned by Mole and must not be touched manually. Even Caches/CodeCache subfolders for these apps are risky.

### System components (touching these breaks macOS)
- `com.apple.*` (entire family for system services)
- `loginwindow`, `dock`, `finder`, `safari`, `systempreferences`
- `com.apple.SystemSettings`, `com.apple.controlcenter*`
- `com.apple.Spotlight`, `com.apple.notificationcenterui`
- `com.apple.SecurityAgent`, `com.apple.securityd`, `com.apple.trustd`
- `com.apple.cloudd`, `com.apple.iCloud*`
- `com.apple.WiFi*`, `com.apple.Bluetooth*`, `com.apple.airport*`
- `com.apple.coreservices*`, `com.apple.metadata*`
- `com.apple.MobileSoftwareUpdate*`, `com.apple.SoftwareUpdate*`
- `com.apple.installer*`
- `com.apple.frameworks*`
- `com.apple.background*`

### Specific known-broken-if-deleted
- **`com.apple.coreaudio` / `coreaudiod`** — Mole issue #553. Deleting cache breaks audio on Intel Macs (Apple Silicon less affected, still avoid).
- **`com.apple.controlcenter*` caches** — Mole issue #136. Causes blank Settings panel on Sonoma/Sequoia/Tahoe.
- **`org.cups.*` (printing subsystem)** — Mole issue #731. Wipes saved printers and recent-printer list.
- **`com.apple.tcc.db`** — TCC permission database. Deleting forces re-grant of every Notification/Camera/Mic/etc. permission.
- **Keychains** (`~/Library/Keychains/*`) — passwords, certificates, tokens. Deletion = lost auth across all apps.

### Input methods (deleting wipes user dictionaries)
- `com.tencent.inputmethod.QQInput`
- `com.sogou.inputmethod.*`
- `com.baidu.inputmethod.*`
- `*.inputmethod`, `*IME`
- `com.apple.inputmethod.*`
- `org.pqrs.Karabiner*` (key remapping — config + license)

### Password managers
- `com.1password.*`
- `com.agilebits.*` (1Password legacy)
- `com.lastpass.*`
- `com.dashlane.*`
- `com.bitwarden.*`
- `com.keepassx*`, `org.keepassx*`, `org.keepassxc.*`
- `com.authy.*`, `com.yubico.*`

### AI tools (chat history is in Application Support)
- `com.anthropic.claude*`, `Claude` — chat history
- `com.openai.chat*`, `ChatGPT`
- **Cursor** (`com.todesktop.*` — Cursor uses ToDesktop)
- `com.ollama.ollama`, `Ollama` — installed models (often 10+ GB but user data)
- `com.lmstudio.lmstudio`, `LM Studio`
- `Gemini`
- `com.perplexity.Perplexity`
- `Antigravity`
- Custom AI editors with chat state

For AI tools, only Cache / Code Cache / GPUCache / Service Worker / CacheStorage subfolders are clearable. Never IndexedDB, Local Storage, or anything outside the cache families.

### Database clients (saved connections, query history, registered databases)
- `com.sequelpro.*`, `com.sequel-ace.*`
- `com.dbeaver.*`
- `com.navicat.*`
- `com.mongodb.compass`
- `com.redis.RedisInsight`
- `com.pgadmin.pgadmin4`
- `com.dbvis.DbVisualizer`
- `com.valentina-db.*`

### API clients (collections, environments, history)
- `com.postmanlabs.mac`
- `com.konghq.insomnia`
- `com.usebruno.app`
- `com.charlesproxy.charles`, `com.CharlesProxy.*`
- `com.proxyman.*`
- `com.luckymarmot.Paw`, `com.getpaw.*`
- `com.telerik.Fiddler`

### VPN / proxy clients
- `com.clash.*`, `ClashX*`, `clash-verge*`
- Shadowsocks, V2Ray
- Tailscale (auth tokens)
- Mullvad, NordVPN, ProtonVPN

### IDEs (project history, settings, indexes)
- `com.jetbrains.*`, `JetBrains*`
- `com.microsoft.VSCode`, `com.microsoft.VSCodeInsiders`
- `com.visualstudio.code.*`
- `com.sublimetext.*`, `com.sublimehq.*`
- `com.apple.dt.Xcode`
- `com.coteditor.CotEditor`, `com.macromates.TextMate`
- `com.panic.Nova`
- `abnerworks.Typora`, `com.uranusjr.macdown`

For IDEs, only logs, caches, indexes, plugin caches are safe. Never user settings, project lists, license files.

---

## User content paths (never auto-clean)

- `~/Library/Mobile Documents/` — iCloud Drive locally synced. User files. Even subdirectories that look like cache (`.DocumentRevisions-V100`) are not actually cache from a user perspective.
- `~/Pictures/Photos Library.photoslibrary` — Photos database. Even with iCloud, the local library bundle is the source of truth for Photos.app. Direct manipulation corrupts the library.
- `~/Library/Messages/` — Messages.app database. `chat.db` and `Attachments/`. Deleting attachments removes them from Messages history.
- `~/Library/Mail/V*/MailData/` — Mail.app local mailboxes (if Mail.app is used).
- `~/Library/Application Support/AddressBook/` — Contacts data.
- `~/Library/Application Support/com.apple.sharedfilelist/` — Recent Items lists, login items.
- `~/.Trash` — only empty if user explicitly OK; recently deleted files may still be wanted.
- `~/Documents`, `~/Desktop`, `~/Pictures`, `~/Movies`, `~/Music` (root level) — user content. Only delete specific files identified individually.

---

## Per-app subfolders that LOOK like cache but contain state

These are inside Application Support but are NOT regenerable. Only the cache-family subfolders (`Cache`, `Code Cache`, `GPUCache`, `Service Worker/CacheStorage`, `DawnCache`, etc.) are clean targets.

| App | Path | What it actually is |
|---|---|---|
| Telegram | `~/Library/Application Support/Telegram Desktop/tdata/` | Full chat history + session keys. Delete = logout + lost local history. |
| Telegram | `~/Library/Group Containers/*.com.tdesktop/` | Same |
| Granola | `~/Library/Application Support/Granola/File System/` | Meeting transcripts and notes |
| Granola | `~/Library/Application Support/Granola/IndexedDB/` | Structured transcript data |
| Notion | `~/Library/Application Support/Notion/Partitions/notion/IndexedDB/` | Offline page data |
| Slack | `~/Library/Application Support/Slack/storage/`, `IndexedDB/` | Workspace prefs, draft messages |
| Arc | `~/Library/Application Support/Arc/User Data/Default/IndexedDB/` | Extension state, 1Password vault refs |
| Arc | `~/Library/Application Support/Arc/User Data/Default/Local Extension Settings/` | Same |
| Zed | `~/Library/Application Support/Zed/db/0-stable/` | LSP index, project history |
| opencode | `~/.local/share/opencode/opencode.db` | Conversation history |
| Codex | `~/.codex/sessions/` | Conversation history (NOT log/) |
| Claude Code | `~/.claude/projects/*/` | Per-project session history |
| Claude Code | `~/Library/Application Support/Claude/vm_bundles/claudevm.bundle/` | **9.7 GB Linux sandbox runtime — active, never delete** |
| Voice Memos | `~/Library/Application Support/com.apple.voicememos/Recordings/` | User audio recordings |
| Notes | `~/Library/Group Containers/group.com.apple.notes/` | Notes content + attachments |

When in doubt for an Application Support folder: only Cache/CodeCache/GPUCache/Service Worker subdirs are safe. Everything else, ask.

---

## OS-level operations that NEVER apply

- `rm -rf /private/var/vm/swapfile*` — guaranteed kernel panic. Live swap files cannot be removed; macOS manages lifecycle.
- `rm /private/var/vm/sleepimage` — only safe if hibernation is disabled first via `sudo pmset -a hibernatemode 0 standby 0`. Otherwise corrupts sleep/wake.
- Force-killing live processes for "memory pressure" — corrupts open file handles. Docker volumes, databases, in-flight git operations, unsaved files. Suggest user close gracefully.
- Auto-emptying Trash — user may still want recent items.
- Auto-cleanup tied to alerts — anti-pattern (Google SRE consensus). Alert notifies; human decides.
- Disabling SIP for "deeper monitoring access" — CVE-2024-44243 demonstrated kernel attack surface. Not justified for personal monitoring.
- Modifying TCC database (`tccutil reset` is fine, direct SQLite edits are not).

---

## How to handle pushback

User says "I know it's risky, just delete it":

1. State the consequence in concrete terms ("you'll lose your last 6 months of meeting transcripts", not "user data").
2. Offer alternative: archive instead of delete, or use the app's own export, or move to external SSD.
3. If they insist, document in chat: confirm exact path, exact action, exact intended effect. Make them say "yes, delete X.path which contains Y, I accept losing Z."
4. Even then, prefer non-destructive: `mv` to `~/.deleted-YYYYMMDD/` instead of `rm`. Easy to recover if they regret it.

Risk is asymmetric: false caution costs them disk space; one bad delete costs them weeks of work. Bias toward caution.
