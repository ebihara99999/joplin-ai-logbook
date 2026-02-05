# joplin-ai-logbook

Sync Claude/Codex JSONL logs into Joplin notes.

## What it does
- Watches Claude and Codex log files.
- Appends new content to Joplin notes, one note per log file.
- Adds tags: `claude`, `codex`.

## Requirements
- Joplin Desktop with Web Clipper enabled.
- `bash`, `curl`, `jq`, `python3`.

## Tested environment
- OS: Ubuntu 22.04.5 LTS (WSL2, kernel `6.6.87.2-microsoft-standard-WSL2`)
- `jq` 1.6
- `zsh` 5.8.1
- `python3` 3.10.12
- `curl` 7.81.0
- Other OSes have not been tested.

## Setup
- Copy `.env.sample` to `.env` next to the scripts and fill in values.

Example `.env`:
```env
JOPLIN_URL=http://127.0.0.1:41184
JOPLIN_TOKEN=xxxxxxxxxxxxxxxxxxxxxxxxxxxx
JOPLIN_NOTEBOOK_TITLE=joplin-ai-logbook
```

Note: `.env` is sourced by the scripts, so only use trusted content.

## Usage
- Run: `./watch-ai-logs.sh`
- Stop: `Ctrl+C`

## Configuration
- `JOPLIN_URL` (default `http://127.0.0.1:41184`)
- `JOPLIN_TOKEN` (required)
- `JOPLIN_NOTEBOOK_TITLE` (default `joplin-ai-logbook`)
- `JOPLIN_ENV_FILE` (optional path to `.env`)
- `CLAUDE_PROJECTS_DIR` (default `~/.claude/projects`)
- `CODEX_SESSIONS_DIR` (default `~/.codex/sessions`)
- `POLL_SEC` (default `5`)

Note: the clipper service port can vary by environment. Check the Web Clipper options in the Joplin desktop app for the current port. Documentation: https://joplinapp.org/help/api/references/rest_api

## Note naming
Notes are created per log file with titles like:
`YYYY-MM-DD <agent> <relative-path>`

Example:
`2026-02-04 claude projectA/conversation.jsonl`

## Troubleshooting
- Make sure Joplin Web Clipper is running. `JOPLIN_URL/ping` should return `JoplinClipperServer`.
- To resync from scratch, delete `~/.ai-log-sync/lastline-*`.

## Error handling
- Invalid JSON lines are skipped without logging.
