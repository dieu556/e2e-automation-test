#!/bin/sh
set -eu

CONFIG_SRC=/opt/baresip/config
CONFIG_DIR=/tmp/baresip

die() {
  echo "baresip: $*" >&2
  exit 1
}

require() {
  key=$1
  eval "value=\${$key:-}"
  if [ -z "$value" ]; then
    die "thieu bien $key. Copy .env.example thanh .env roi dien gia tri Twilio."
  fi
}

require TWILIO_TERMINATION_URI
require TWILIO_CALLER_ID

termination=$(printf '%s' "$TWILIO_TERMINATION_URI" | sed -e 's#^[sS][iI][pP][sS]\?:##' -e 's#/.*$##')
caller_id=$TWILIO_CALLER_ID
proxy=${TWILIO_OUTBOUND_PROXY:-pstn.singapore.twilio.com}
proxy=$(printf '%s' "$proxy" | sed -e 's#^[sS][iI][pP][sS]\?:##' -e 's#;.*$##')
transport=$(printf '%s' "${SIP_TRANSPORT:-tcp}" | tr '[:upper:]' '[:lower:]')
username=${TWILIO_SIP_USERNAME:-}
password=${TWILIO_SIP_PASSWORD:-}

case "$transport" in
  udp|tcp|tls) ;;
  *) die "SIP_TRANSPORT phai la udp, tcp hoac tls" ;;
esac

case "$caller_id" in
  +[0-9]*) ;;
  *) die "TWILIO_CALLER_ID phai la E.164, vi du +15551234567" ;;
esac

if [ -n "$username" ] && [ -z "$password" ]; then
  die "da co TWILIO_SIP_USERNAME nhung thieu TWILIO_SIP_PASSWORD"
fi

case "$password" in
  *";"*|*"\""*|[[:space:]]*)
    die "TWILIO_SIP_PASSWORD khong duoc chua dau cach, dau ; hoac dau nhay kep"
    ;;
esac

modpath=$(find /usr -type f -name g711.so -path '*/baresip/*' 2>/dev/null | head -n 1 || true)
if [ -z "$modpath" ]; then
  die "khong tim thay g711.so trong image baresip"
fi
modpath=$(dirname "$modpath")

stdio_line="# module stdio.so"
if [ -t 0 ]; then
  stdio_line="module stdio.so"
fi

mkdir -p "$CONFIG_DIR"
sed -e "s|__MODULE_PATH__|${modpath}|" -e "s|__STDIO_LINE__|${stdio_line}|" \
  "$CONFIG_SRC" > "$CONFIG_DIR/config"

auth=""
if [ -n "$username" ]; then
  auth=$(printf ';auth_user=%s;auth_pass=%s' "$username" "$password")
fi

# Caller ID nam o user-part cua From. Username digest la auth_user, tach rieng.
# regint=0: Elastic SIP Trunk termination khong can REGISTER.
printf '<sip:%s@%s;transport=%s>;regint=0%s;outbound="sip:%s;transport=%s";audio_codecs=pcmu/8000/1,pcma/8000/1;ptime=20;medianat=stun;stunserver="stun:stun.l.google.com:19302";catchall=yes\n' \
  "$caller_id" "$termination" "$transport" "$auth" "$proxy" "$transport" \
  > "$CONFIG_DIR/accounts"
: > "$CONFIG_DIR/contacts"
chmod 700 "$CONFIG_DIR"
chmod 600 "$CONFIG_DIR/accounts" "$CONFIG_DIR/config"

echo "baresip: trunk ${termination} via ${proxy} transport=${transport} caller=${caller_id}" >&2

if [ -t 0 ]; then
  echo "Lenh goi thu: /dial sip:+E164@${termination};transport=${transport}" >&2
  exec /usr/bin/baresip -4 -f "$CONFIG_DIR"
fi

exec /usr/bin/baresip -4 -f "$CONFIG_DIR"
