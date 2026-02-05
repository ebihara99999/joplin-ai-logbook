#!/usr/bin/env bash
set -euo pipefail

DIR_STATE="${HOME}/.ai-log-sync"
mkdir -p "$DIR_STATE"

: "${CLAUDE_PROJECTS_DIR:=${HOME}/.claude/projects}"
: "${CODEX_SESSIONS_DIR:=${HOME}/.codex/sessions}"
: "${POLL_SEC:=5}"

source "$(dirname "$0")/joplin-lib.sh"

last_line_file_for() {
  local f="$1"
  local key
  key="$(printf "%s" "$f" | sha1sum | awk '{print $1}')"
  echo "${DIR_STATE}/lastline-${key}"
}

get_last_line() {
  local lf="$1"
  [[ -f "$lf" ]] && cat "$lf" || echo "1"
}

set_last_line() {
  local lf="$1"
  local line="$2"
  echo "$line" > "$lf"
}

# 「最近更新されたファイルを全部拾う」: これで rollout が複数あってもOK
find_recent_claude_files() {
  find "$CLAUDE_PROJECTS_DIR" -type f -name "*.jsonl" -mmin -1440 2>/dev/null \
  -print0 | xargs -0 -r ls -t 2>/dev/null
}

find_recent_codex_files() {
  find "$CODEX_SESSIONS_DIR" -type f -name "rollout-*.jsonl" -mmin -1440 2>/dev/null \
  -print0 | xargs -0 -r ls -t 2>/dev/null
}

sync_one_file() {
  local source_name="$1"   # claude or codex
  local file="$2"

  [[ -z "$file" ]] && return 0
  [[ ! -f "$file" ]] && return 0

  local lf; lf="$(last_line_file_for "$file")"
  local from; from="$(get_last_line "$lf")"
  local total; total="$(wc -l < "$file" | tr -d ' ')"

  # file rotated or truncated
  if [[ "$total" -lt "$from" ]]; then
    set_last_line "$lf" "$((total+1))"
    return 0
  fi
  # no new lines
  if [[ "$total" -lt "$from" ]] || [[ "$total" -eq "$from" ]]; then
    return 0
  fi

  local new_content=""
  if [[ "$source_name" == "claude" ]]; then
    new_content="$(./extract-claude.sh "$file" "$from")"
  else
    new_content="$(./extract-codex.sh "$file" "$from")"
  fi

  # advance cursor to next line after current total
  set_last_line "$lf" "$((total+1))"

  [[ -z "$new_content" ]] && return 0

  joplin_ping

  local folder_id
  folder_id="$(get_or_create_folder_id "$JOPLIN_NOTEBOOK_TITLE")"

  local day
  day="$(date +%Y-%m-%d)"

  local rel_path
  if [[ "$source_name" == "claude" ]]; then
    rel_path="${file#${CLAUDE_PROJECTS_DIR}/}"
  else
    rel_path="${file#${CODEX_SESSIONS_DIR}/}"
  fi
  [[ "$rel_path" == "$file" ]] && rel_path="$(basename "$file")"

  local note_title
  note_title="${day} ${source_name} ${rel_path}"

  local note_id
  note_id="$(get_or_create_daily_note_id "$folder_id" "$note_title")"

  # セッション情報をコンパクトに
  local time_now
  time_now="$(date +%H:%M)"
  local short_file
  short_file="$rel_path"

  local block
  block=$'\n'"---"$'\n'"### ${source_name} - ${time_now}"$'\n'"<small>${short_file}</small>"$'\n\n'"${new_content}"

  append_to_note "$note_id" "$block"

  # Tag note with source (claude/codex)
  local tag_id
  tag_id="$(get_or_create_tag_id "$source_name")"
  attach_tag_to_note "$tag_id" "$note_id"
}

echo "joplin-ai-logbook: Watching Claude/Codex logs and syncing to Joplin... (poll ${POLL_SEC}s)"

while true; do
  # Claude: 最近更新された jsonl を上から順に処理（lastlineで増分のみ）
  while read -r f; do
    [[ -z "$f" ]] && continue
    sync_one_file "claude" "$f"
  done < <(find_recent_claude_files)

  # Codex: rollout-*.jsonl を上から順に処理（lastlineで増分のみ）
  while read -r f; do
    [[ -z "$f" ]] && continue
    sync_one_file "codex" "$f"
  done < <(find_recent_codex_files)

  sleep "$POLL_SEC"
done
