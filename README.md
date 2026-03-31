# Mango Costs 🥭

A lightweight macOS menu bar app that tracks your [Claude Code (OpenClaw)](https://claude.ai/code) session costs and token usage in real time.

![Session tab showing cost, token breakdown, and context window usage]

## Features

- **Session tab** — live cost, input/output/cache tokens, context window bar, session duration
- **Total tab** — all-time cost and token totals across every session
- **Context window bar** — shows % of the model's context window used by the last request (colour-coded green → amber → red)
- **Cost notifications** — desktop alerts at $0.10, $0.50, and $1.00 thresholds
- **Native macOS window** — transparent title bar, traffic light buttons, vibrancy material

## Requirements

- macOS 13 Ventura or later
- Xcode 15+ (to build from source)
- [Claude Code](https://claude.ai/code) — the app reads session data from `~/.openclaw/agents/main/sessions/`

## Install

### 1. Clone

```bash
git clone https://github.com/ethanrozee/mango-costs.git
cd mango-costs
```

### 2. Install the CLI

```bash
bash install.sh
```

This symlinks `scripts/mango-costs` into `~/.local/bin/mango-costs`. Make sure `~/.local/bin` is on your `$PATH` (add `export PATH="$HOME/.local/bin:$PATH"` to your `.zshrc` if not).

### 3. Build and install the app

```bash
mango-costs update
```

This compiles the Xcode project, kills any running instance, and copies the fresh build to `/Applications/MangoCosts.app`.

### 4. Launch

```bash
mango-costs show
```

The app appears in the top-right corner of your screen. Click the 🥭 menu bar icon to toggle it.

## CLI commands

| Command | Description |
|---|---|
| `mango-costs show` | Launch (or bring to front) the app |
| `mango-costs status` | Print current session stats in the terminal |
| `mango-costs update` | Rebuild from source and reinstall to `/Applications` |

## Updating

After pulling new changes, just run:

```bash
mango-costs update
```

## How it works

Mango Costs polls two files every 30 seconds:

- `~/.openclaw/agents/main/sessions/sessions.json` — session metadata (model, context size, session file path)
- The JSONL file referenced in `sessions.json` — per-message token and cost data

Token totals are summed across all assistant messages in the JSONL. The context window bar uses the most recent assistant message's input token count (which reflects the actual prompt size sent to the model, not a cumulative total).

## Building manually (without the CLI)

```bash
xcodebuild -project MangoCosts.xcodeproj \
  -scheme MangoCosts \
  -configuration Debug \
  build \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO

# Find and install the built app
BUILD_APP=$(find ~/Library/Developer/Xcode/DerivedData/MangoCosts-*/Build/Products/Debug/MangoCosts.app -maxdepth 0 2>/dev/null | head -1)
rm -rf /Applications/MangoCosts.app
cp -R "$BUILD_APP" /Applications/MangoCosts.app
open /Applications/MangoCosts.app
```
