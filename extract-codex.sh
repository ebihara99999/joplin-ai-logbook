#!/usr/bin/env bash
set -euo pipefail

file="$1"
from_line="${2:-1}"

# もし「行頭に番号が混ざってる」ファイルがあるなら、↓の sed を有効化してから jq に渡す:
# tail -n +"$from_line" "$file" | sed -E 's/^[0-9]+[[:space:]]+//' | jq -r '...'

# fromjson? skips invalid JSON lines; no logging by design.
tail -n +"$from_line" "$file" \
| jq -R -r '
  def time_from_ts:
    ((.timestamp // "") | tostring) as $ts
    | ($ts | split("T") | .[1] // "") as $t1
    | ($t1 | split(".")[0] | split("Z")[0] | split("+")[0] | split("-")[0]);

  fromjson?
  | select(type == "object")
  | (time_from_ts // "") as $time
  |
  if (.type=="event_msg" and .payload.type=="user_message") then
    "**\($time) ユーザー**\n\(.payload.message // "")\n"

  elif (.type=="response_item" and .payload.type=="message" and .payload.role=="assistant") then
    ((.payload.content // [])
      | map(
          if .type=="output_text" then (.text // "")
          elif .type=="summary_text" then (.text // "")
          else "" end
        )
      | join("")) as $content
    | "**\($time) Codex**\n\($content)\n"

  else
    empty
  end
' || true
