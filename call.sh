#!/bin/bash
# Dat mot cuoc outbound qua baresip trong Docker.
# Usage: ./scripts/call.sh [+E164] [seconds]
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$ROOT"

if [ ! -f .env ]; then
  echo "Chua co .env. Chay: cp .env.example .env" >&2
  exit 1
fi

env_value() {
  key=$1
  line=$(grep -E "^${key}=" .env | tail -n 1 || true)
  printf '%s' "${line#*=}"
}

dest=${1:-$(env_value DESTINATION)}
seconds=${2:-$(env_value CALL_SECONDS)}
seconds=${seconds:-20}
termination=$(env_value TWILIO_TERMINATION_URI)
termination=${termination#sip:}
termination=${termination#sips:}
termination=${termination%%/*}
transport=$(env_value SIP_TRANSPORT)
transport=${transport:-tcp}
transport=$(printf '%s' "$transport" | tr '[:upper:]' '[:lower:]')

case "$dest" in
  +[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]*) ;;
  *)
    echo "So dich phai la E.164, vi du: ./scripts/call.sh +84901234567" >&2
    exit 1
    ;;
esac

if [ -z "$termination" ] || [ "$termination" = "your-trunk.pstn.twilio.com" ]; then
  echo "Dien TWILIO_TERMINATION_URI that trong .env truoc khi goi." >&2
  exit 1
fi

uri="sip:${dest}@${termination};transport=${transport}"
echo "Goi ${uri}"
echo "Giu ${seconds}s roi cup may. Ctrl+C de dung som."

docker compose up -d --force-recreate

cleanup() {
  exec 3<&- 2>/dev/null || true
  exec 3>&- 2>/dev/null || true
  docker compose down --timeout 3 >/dev/null 2>&1 || true
}
trap cleanup EXIT

ready=0
for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30; do
  running=$(docker inspect -f '{{.State.Running}}' baresip-twilio 2>/dev/null || echo false)
  if [ "$running" != "true" ]; then
    echo "Container da thoat:" >&2
    docker logs baresip-twilio >&2 || true
    exit 1
  fi
  if docker logs baresip-twilio 2>&1 | grep -q "baresip is ready"; then
    ready=1
    break
  fi
  sleep 0.5
done

if [ "$ready" -ne 1 ]; then
  echo "baresip khong san sang. Log:" >&2
  docker logs baresip-twilio >&2 || true
  exit 1
fi

exec 3<>/dev/tcp/127.0.0.1/4444

send_cmd() {
  json=$1
  printf '%s:%s,' "${#json}" "$json" >&3
}

send_cmd "{\"command\":\"dial\",\"params\":\"${uri}\",\"token\":\"dial\"}"

start=$SECONDS
while [ $((SECONDS - start)) -lt "$seconds" ]; do
  chunk=""
  if IFS= read -r -t 1 -n 500 chunk <&3; then
    printf '%s' "$chunk"
  fi
done
printf '\n'

send_cmd "{\"command\":\"hangup\",\"token\":\"hangup\"}"
sleep 1
chunk=""
if IFS= read -r -t 1 -n 500 chunk <&3; then
  printf '%s\n' "$chunk"
fi

echo "--- baresip log ---"
docker logs baresip-twilio || true
