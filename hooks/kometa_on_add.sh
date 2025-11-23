#!/bin/bash
# Usage: kometa_on_add.sh {media_type} "{section_name}"

MEDIA_TYPE="$1"
LIB_NAME="$2"
TARGET_LIBRARY="TV Shows"

KOMETA_CONTAINER="$(docker ps --format '{{.Names}}' | awk 'tolower($0)=="kometa"{print; exit}')"
if [[ -z "$KOMETA_CONTAINER" ]]; then
  KOMETA_CONTAINER="$(docker ps --format '{{.Names}}' | grep -i '^kometa$' || docker ps --format '{{.Names}}' | grep -i kometa | head -n1)"
fi
if [[ -z "$KOMETA_CONTAINER" ]]; then
  echo "$(date '+%F %T') error: Kometa container not found" >> /mnt/user/appdata/kometa/hooks/kometa_on_add.log
  exit 1
fi

KOMETA_CMD="python3 kometa.py --run --libraries \"${TARGET_LIBRARY}\" --overlays-only --metadata-only"
LOGFILE="/mnt/user/appdata/kometa/hooks/kometa_on_add.log"

# Only trigger for episodes in the right library
if [[ "$MEDIA_TYPE" != "episode" ]]; then
  echo "$(date '+%F %T') skip (not episode): $MEDIA_TYPE" >> "$LOGFILE"; exit 0; fi
if [[ "$LIB_NAME" != "$TARGET_LIBRARY" ]]; then
  echo "$(date '+%F %T') skip (wrong library): $LIB_NAME" >> "$LOGFILE"; exit 0; fi

echo "$(date '+%F %T') >>> Running Kometa overlay for Big Brother (prefix match)" >> "$LOGFILE"
docker exec -t "$KOMETA_CONTAINER" bash -lc "$KOMETA_CMD" >> "$LOGFILE" 2>&1
EXIT=$?
echo "$(date '+%F %T') kometa exit=$EXIT" >> "$LOGFILE"

# Trim logfile to last 100 lines
TMPLOG=$(mktemp)
tail -n 100 "$LOGFILE" > "$TMPLOG"
mv "$TMPLOG" "$LOGFILE"

exit $EXIT
