#!/bin/bash
# Usage in Tautulli: kometa_on_add.sh {media_type} "{section_name}" "{show_title}"
# If you can't pass show_title, the script still works (it will blur all TV Shows overlays).

MEDIA_TYPE="$1"
LIB_NAME="$2"
SHOW_TITLE="$3"             # Optional: pass {show_name} from Tautulli to limit scope
TARGET_LIBRARY="TV Shows"
PLEX_BASE="http://192.168.1.228:32400"
PLEX_TOKEN="d7HBhUi1F8dRXTQsNSoW"
TV_SECTION_ID="2"           # <-- set to your TV library section id

LOGFILE="/mnt/user/appdata/kometa/hooks/kometa_on_add.log"

# Find kometa container (case-insensitive fallback)
KOMETA_CONTAINER="$(docker ps --format '{{.Names}}' | awk 'tolower($0)=="kometa"{print; exit}')"
if [[ -z "$KOMETA_CONTAINER" ]]; then
  KOMETA_CONTAINER="$(docker ps --format '{{.Names}}' | grep -i '^kometa$' || docker ps --format '{{.Names}}' | grep -i kometa | head -n1)"
fi
if [[ -z "$KOMETA_CONTAINER" ]]; then
  echo "$(date '+%F %T') error: Kometa container not found" >> "$LOGFILE"
  exit 1
fi

# Only trigger for new EPISODES in the TV Shows library
if [[ "$MEDIA_TYPE" != "episode" ]]; then
  echo "$(date '+%F %T') skip (not episode): $MEDIA_TYPE" >> "$LOGFILE"
  exit 0
fi
if [[ "$LIB_NAME" != "$TARGET_LIBRARY" ]]; then
  echo "$(date '+%F %T') skip (wrong library): $LIB_NAME" >> "$LOGFILE"
  exit 0
fi

# Build kometa command:
#  - overlays-only (DO NOT include --metadata-only)
#  - optional collection filter for speed/precision
KOMETA_CMD_BASE='python3 kometa.py --run --libraries "TV Shows" --overlays-only'
if [[ -n "$SHOW_TITLE" ]]; then
  # If your overlay relies on collection or title match, this is a quick limiter.
  KOMETA_CMD="$KOMETA_CMD_BASE --collections \"$SHOW_TITLE\""
else
  KOMETA_CMD="$KOMETA_CMD_BASE"
fi

# Helper: run kometa once, capture exit + a quick success heuristic
run_kometa_once() {
  echo "$(date '+%F %T') >>> Running Kometa overlays (container=$KOMETA_CONTAINER) cmd: $KOMETA_CMD" >> "$LOGFILE"
  # shellcheck disable=SC2086
  docker exec -t "$KOMETA_CONTAINER" bash -lc "$KOMETA_CMD" >> "$LOGFILE" 2>&1
  local rc=$?
  # Heuristic: if Kometa logs show 0 items, we’ll retry
  local applied
  applied="$(tail -n 200 "$LOGFILE" | grep -Ei 'Applying overlay|Applied overlay|overlays? applied|items? processed' | tail -n 1)"
  echo "$(date '+%F %T') kometa exit=$rc; last_apply_line=${applied:-<none>}" >> "$LOGFILE"
  return $rc
}

# Step 1) Ask Plex to refresh the TV library so the new ep is visible
echo "$(date '+%F %T') Plex library refresh (section=$TV_SECTION_ID)" >> "$LOGFILE"
curl -sf "$PLEX_BASE/library/sections/$TV_SECTION_ID/refresh?X-Plex-Token=$PLEX_TOKEN" >/dev/null || true

# Step 2) Small wait for indexing to complete (tune as needed)
sleep 8

# Step 3) Run Kometa overlays; retry if it likely ran too early
MAX_TRIES=3
DELAY=12

try=1
while : ; do
  run_kometa_once
  # If Kometa ran successfully, break. Even if exit code is 0, it may have done 0 work due to timing;
  # we also retry on that case by inspecting the recent log line.
  # If you want stricter detection (grep for "0 items"), you can add that here.

  # Look for a signal that something was applied — if not, retry
  if tail -n 200 "$LOGFILE" | grep -Eiq 'Applied overlay|overlays? applied|Updating|Wrote|Processed [1-9]'; then
    echo "$(date '+%F %T') success: overlay likely applied" >> "$LOGFILE"
    break
  fi

  if [[ $try -ge $MAX_TRIES ]]; then
    echo "$(date '+%F %T') giving up after $try tries (likely early run or overlay filter mismatch)" >> "$LOGFILE"
    break
  fi

  echo "$(date '+%F %T') retry $try/$MAX_TRIES after $DELAY s (waiting for Plex to finish ingesting)" >> "$LOGFILE"
  sleep "$DELAY"
  try=$((try+1))
  # optional: backoff
  DELAY=$((DELAY + 8))
done

# Trim logfile to last 200 lines
TMPLOG=$(mktemp)
tail -n 200 "$LOGFILE" > "$TMPLOG" && mv "$TMPLOG" "$LOGFILE"
exit 0