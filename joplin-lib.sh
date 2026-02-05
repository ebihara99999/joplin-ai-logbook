#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${JOPLIN_ENV_FILE:-${SCRIPT_DIR}/.env}"
if [[ -f "$ENV_FILE" ]]; then
  set -a
  # shellcheck source=/dev/null
  . "$ENV_FILE"
  set +a
fi

: "${JOPLIN_URL:=${JOPLIN_BASE:-http://127.0.0.1:41184}}"
: "${JOPLIN_TOKEN:?Set JOPLIN_TOKEN env var}"
: "${JOPLIN_NOTEBOOK_TITLE:=joplin-ai-logbook}"

# キャッシュ用連想配列
declare -A _FOLDER_CACHE
declare -A _NOTE_CACHE

urlenc() {
  python3 - << 'PY'
import urllib.parse, sys
print(urllib.parse.quote(sys.stdin.read().strip()))
PY
}

joplin_ping() {
  # /ping returns "JoplinClipperServer" when the clipper server is up
  curl -fsS "${JOPLIN_URL}/ping" >/dev/null
}

get_or_create_folder_id() {
  local title="$1"

  # キャッシュチェック
  if [[ -n "${_FOLDER_CACHE[$title]:-}" ]]; then
    echo "${_FOLDER_CACHE[$title]}"; return
  fi

  local response
  response="$(curl -s "${JOPLIN_URL}/folders?fields=id,title&limit=100&token=${JOPLIN_TOKEN}")"

  local id
  id="$(echo "$response" | jq -r --arg title "$title" '.items[] | select(.title == $title) | .id' | head -n1)"

  if [[ -n "$id" ]]; then
    _FOLDER_CACHE[$title]="$id"
    echo "$id"; return
  fi

  id="$(curl -s --data "$(jq -nc --arg title "$title" '{title:$title}')" \
    "${JOPLIN_URL}/folders?token=${JOPLIN_TOKEN}" | jq -r '.id')"
  _FOLDER_CACHE[$title]="$id"
  echo "$id"
}

get_or_create_daily_note_id() {
  local folder_id="$1"
  local day="$2"   # YYYY-MM-DD
  local title="$day"
  local cache_key="${folder_id}:${title}"

  # キャッシュチェック
  if [[ -n "${_NOTE_CACHE[$cache_key]:-}" ]]; then
    echo "${_NOTE_CACHE[$cache_key]}"; return
  fi

  local response
  response="$(curl -s "${JOPLIN_URL}/folders/${folder_id}/notes?fields=id,title&limit=100&token=${JOPLIN_TOKEN}")"

  local id
  id="$(echo "$response" | jq -r --arg title "$title" '.items[] | select(.title == $title) | .id' | head -n1)"

  if [[ -n "$id" ]]; then
    _NOTE_CACHE[$cache_key]="$id"
    echo "$id"; return
  fi

  id="$(curl -s --data "$(jq -nc \
    --arg title "$title" \
    --arg parent_id "$folder_id" \
    --arg body "# ${title}" \
    '{title:$title, parent_id:$parent_id, body:$body}')" \
    "${JOPLIN_URL}/notes?token=${JOPLIN_TOKEN}" | jq -r '.id')"
  _NOTE_CACHE[$cache_key]="$id"
  echo "$id"
}

append_to_note() {
  local note_id="$1"
  local new_content="$2"

  local current
  current="$(
    curl -s "${JOPLIN_URL}/notes/${note_id}?fields=body&token=${JOPLIN_TOKEN}" | jq -r '.body'
  )"

  local updated="${current}"$'\n'"${new_content}"$'\n'
  printf '%s' "$updated" \
    | jq -Rs '{body: .}' \
    | curl -s -X PUT --data-binary @- \
      "${JOPLIN_URL}/notes/${note_id}?token=${JOPLIN_TOKEN}" >/dev/null
}

get_or_create_tag_id() {
  local tag_title="$1"
  local q; q="$(printf "%s" "$tag_title" | urlenc)"

  local id
  id="$(
    curl -s "${JOPLIN_URL}/search?query=${q}&type=tag&fields=id,title&token=${JOPLIN_TOKEN}" \
      | jq -r --arg title "$tag_title" '.items[]? | select(.title==$title) | .id' | head -n1
  )"

  if [[ -n "$id" ]]; then
    echo "$id"; return
  fi

  curl -s --data "$(jq -nc --arg title "$tag_title" '{title:$title}')" \
    "${JOPLIN_URL}/tags?token=${JOPLIN_TOKEN}" | jq -r '.id'
}

attach_tag_to_note() {
  local tag_id="$1"
  local note_id="$2"

  curl -s --data "$(jq -nc --arg id "$note_id" '{id:$id}')" \
    "${JOPLIN_URL}/tags/${tag_id}/notes?token=${JOPLIN_TOKEN}" >/dev/null
}
