#!/usr/bin/env bash
set -euo pipefail

file="$1"
from_line="${2:-1}"

# fromjson? skips invalid JSON lines; no logging by design.
tail -n +"$from_line" "$file" \
| jq -R -r '
  def time_from_ts:
    ((.timestamp // "") | tostring) as $ts
    | ($ts | split("T") | .[1] // "") as $t1
    | ($t1 | split(".")[0] | split("Z")[0] | split("+")[0] | split("-")[0]);

  fromjson?
  | select(type == "object")
  | select(.type == "user" or .type == "assistant")
  | (time_from_ts // "") as $time
  | if .type == "user" then
      (.message.content // .content // "") as $content
      | if ($content | type) == "string" and ($content | length > 0) then
          "**\($time) ユーザー**\n\($content)\n"
        else empty end

    elif .type == "assistant" then
      if (.message.content | type) == "array" then
        (.message.content
          | map(select(.type == "text") | select((.text // "") | length > 0) | .text)
          | if length > 0 then
              "**\($time) Claude**\n\(join("\n"))\n"
            else empty end)
      else empty end
    else empty end
' || true
