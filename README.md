# Claude Code Status Bar

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
![Shell](https://img.shields.io/badge/shell-bash-4EAA25?logo=gnubash&logoColor=white)
![Platform](https://img.shields.io/badge/platform-macOS-000000?logo=apple&logoColor=white)

A two-line status bar for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) (the Anthropic CLI) that shows what the built-in statusline doesn't: your **real Pro/Max plan usage** (5h / 7d / 7d Opus, pulled straight from Anthropic's own OAuth endpoint), a live **context window** gauge, and at-a-glance **system stats** (CPU, RAM, disk, battery) — all in a compact, color-coded, single-file bash script with zero dependencies beyond `jq` and `curl`.

If you've ever wondered *"how close am I to my 5-hour limit right now"* without running `/status` by hand, this is for you.

## Preview

```
Opus 4.7 │ 🧩 CTX: ▮▮▯▯▯▯▯▯▯▯ 18% │ 💎 ▮▯▯▯▯▯▯▯▯▯ 7% (55m) │ 📆 7d: 12% (4d12h)
🕐 07:04 │ 📁 ~/D/P/project │ 💾 142GB │ 🧠 8.2GB │ ⚙ 23% │ ⚡ 87%
```

## What it shows

### Line 1 — AI usage
| Segment | Description |
|---------|------|
| **Model** | Active model name (e.g. `Opus 4.7`, `Sonnet 4.6`) |
| **🧩 CTX** | Current session's context window usage (bar + %) |
| **💎** | Usage in the current **5-hour** rolling window + time until reset |
| **📆 7d** | Weekly plan usage + time until reset |
| **🧠 Opus** | Separate 7-day Opus counter (Max plan; hidden at 0%) |

### Line 2 — System
| Segment | Description |
|---------|------|
| **🕐 Clock** | Current time |
| **📁 Directory** | Shortened working directory path |
| **💾 Disk** | Free disk space |
| **🧠 RAM** | Free memory |
| **⚙ CPU** | CPU load |
| **🔋/⚡ Battery** | Charge level + power source (battery/AC) |

## Color coding

Percentage values are colored by severity:
- **Green** — below 50%
- **Yellow** — 50-74%
- **Orange** — 75-89%
- **Red** — 90%+

## Where the usage data comes from

Since Claude Code 2.x, 5h/7d plan limits are tracked **server-side** by Anthropic. Older scripts based on `ccusage blocks` show `100% of 0` because the local JSONL logs no longer carry the full picture.

This script queries the same endpoint Claude Code itself uses for `/status`:

```
GET https://api.anthropic.com/api/oauth/usage
Authorization: Bearer <accessToken from Keychain>
anthropic-beta: oauth-2025-04-20
```

The OAuth token is read straight from the macOS Keychain (`security find-generic-password -s "Claude Code-credentials"`). Results are cached for 5 minutes.

If the Keychain or the endpoint is unreachable, the 5h/7d sections hide themselves automatically — the rest of the bar keeps working.

## Requirements

- **macOS** (uses `top`, `vm_stat`, `pmset`, `df`, `security`)
- **[jq](https://jqlang.org/)** — JSON parsing
- **curl** — OAuth endpoint calls
- A Claude Code session signed in to a Pro/Max plan (for the 5h/7d sections)

## Installation

```bash
cp statusline.sh ~/.claude/statusline.sh
chmod +x ~/.claude/statusline.sh
```

Add to `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "/Users/YOUR_USERNAME/.claude/statusline.sh",
    "refreshInterval": 300
  }
}
```

`refreshInterval` (seconds, requires Claude Code ≥ 2.1.128) forces the status bar to refresh on a timer — without it, the bar only updates on events (prompt submit, model response), so data can go stale after a while idle. 300s = every 5 minutes, matching the OAuth usage cache.

To avoid a permission prompt on every refresh, add these to `permissions.allow`:

```json
"Bash(security find-generic-password:*)",
"Bash(curl * api.anthropic.com/api/oauth/usage*)"
```

Restart Claude Code — the bar appears at the bottom of the terminal.

## Auto-update on session start (optional)

`check-statusline-update.sh` is a Claude Code `SessionStart` hook that checks, on every new session, whether your local `statusline.sh` has the same blob SHA as the `main` branch here. If not, it backs up the current file and swaps in the newer one. Silent when already up to date.

Install:

```bash
cp check-statusline-update.sh ~/.claude/check-statusline-update.sh
chmod +x ~/.claude/check-statusline-update.sh
```

Add to `~/.claude/settings.json` (`hooks` section):

```json
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "command",
            "command": "/Users/YOUR_USERNAME/.claude/check-statusline-update.sh"
          }
        ]
      }
    ]
  }
}
```

Logs go to `~/.claude/statusline-update.log`. Requires: `git`, `curl`, `jq` (already needed by `statusline.sh`). Network timeout: 3-5s — never blocks session startup, even offline.

## Configuration

At the top of the script:

```bash
CC_USAGE_ENDPOINT="https://api.anthropic.com/api/oauth/usage"
CC_KEYCHAIN_SERVICE="Claude Code-credentials"
CC_USER_AGENT="claude-code/2.0.32"
```

## Cache

| Data | TTL | File |
|------|-----|------|
| Plan usage (OAuth) | 5 min | `/tmp/.cc_usage_limits` |
| CPU | 60s | `/tmp/.cc_cpu_cache` |
| RAM | 60s | `/tmp/.cc_ram_cache` |
| Disk | 10 min | `/tmp/.cc_disk_cache` |
| Battery | 60s | `/tmp/.cc_bat_cache` |

## How it works

1. Claude Code invokes the script every few seconds, passing the session JSON on stdin.
2. The script reads the model name and `context_window.remaining_percentage` (falling back to the legacy token-count format when needed).
3. It fetches the OAuth token from Keychain and queries the `api/oauth/usage` endpoint for real 5h/7d/Opus usage.
4. It collects system stats (CPU, RAM, disk, battery) via native macOS tools.
5. It renders everything as two color-coded lines with bar graphs and left/right alignment.

## Contributing

Issues and pull requests are welcome — new segments, other platforms, alternate bar styles, whatever makes this more useful for your setup.

## Credits / sources

- [codelynx.dev — Claude Code Usage Limits Statusline](https://codelynx.dev/posts/claude-code-usage-limits-statusline)
- Related issues: [#15366](https://github.com/anthropics/claude-code/issues/15366), [#12520](https://github.com/anthropics/claude-code/issues/12520), [#15931](https://github.com/anthropics/claude-code/issues/15931)

## License

MIT — see [LICENSE](LICENSE). Free to use, modify, and redistribute. If you fork or reuse this script, keeping a credit line back to the original author (**Intuicja**) is appreciated.
