#!/usr/bin/env bash
# Unit test for home/dot_local/bin/executable_archfrican-bcv.
#
# Black-box: runs the real script against a fake HOME and stub curl/notify-send, so no test touches
# the network or the user's notification daemon. The fixtures cover the whole published set (USD and
# EUR, official and parallel), because the bar's tooltip and click notification must list every rate
# — not just the official one the pill displays.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT="$(cd -- "$HERE/../.." && pwd)"
SCRIPT="$ROOT/home/dot_local/bin/executable_archfrican-bcv"

P=0; F=0
_ok(){ printf '  \033[32mok\033[0m   %s\n' "$1"; P=$((P + 1)); }
_no(){ printf '  \033[31mFAIL\033[0m %s\n' "$1"; F=$((F + 1)); }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
export HOME="$WORK/home"
export XDG_CONFIG_HOME="$HOME/.config"
mkdir -p "$HOME" "$WORK/fakebin"

# Stub curl: log every call, route each endpoint to its fixture, or fail on demand. The fallback to
# /dolares/oficial is routed too, so an outage test can prove both requests were attempted.
cat > "$WORK/fakebin/curl" <<'STUB'
#!/bin/sh
printf 'call %s\n' "$*" >> "$CURL_LOG"
[ "${CURL_FAIL:-0}" = 1 ] && exit 22
case "$*" in
  *"/euros"*)            cat "$EUR_FIXTURE" ;;
  *"/dolares/oficial"*)  cat "$OFFICIAL_FIXTURE" ;;
  *"/dolares"*)          cat "$USD_FIXTURE" ;;
  *)                     cat "$USD_FIXTURE" ;;
esac
STUB
chmod +x "$WORK/fakebin/curl"

cat > "$WORK/fakebin/notify-send" <<'STUB'
#!/bin/sh
printf '%s\n' "$*" > "$NOTIFY_LOG"
STUB
chmod +x "$WORK/fakebin/notify-send"
export PATH="$WORK/fakebin:$PATH"
export CURL_LOG="$WORK/calls" NOTIFY_LOG="$WORK/notify"

fresh_cache() {
  export XDG_CACHE_HOME="$WORK/cache-$1"
  rm -rf "$XDG_CACHE_HOME"
  rm -f "$CURL_LOG" "$NOTIFY_LOG"
}

run() { bash "$SCRIPT" "$@"; }
field() { printf '%s' "$1" | python3 -c 'import json,sys; print(json.load(sys.stdin).get(sys.argv[1],""))' "$2"; }

cat > "$WORK/usd.json" <<'JSON'
[
  {"moneda":"USD","fuente":"oficial","nombre":"Dólar","compra":null,"venta":null,
   "promedio":911.6243,"fechaActualizacion":"2026-11-13T00:00:00-04:00"},
  {"moneda":"USD","fuente":"paralelo","nombre":"Paralelo","compra":null,"venta":null,
   "promedio":1070.339837,"fechaActualizacion":"2026-11-13T13:00:57.677Z"}
]
JSON
cat > "$WORK/eur.json" <<'JSON'
[
  {"moneda":"EUR","fuente":"oficial","nombre":"Euro","compra":null,"venta":null,
   "promedio":1009.34130871,"fechaActualizacion":"2026-11-13T00:00:00-04:00"},
  {"moneda":"EUR","fuente":"paralelo","nombre":"Paralelo","compra":null,"venta":null,
   "promedio":1181.235397,"fechaActualizacion":"2026-11-13T13:00:57.711Z"}
]
JSON
cat > "$WORK/official.json" <<'JSON'
{"moneda":"USD","fuente":"oficial","nombre":"Dólar","compra":null,"venta":null,
 "promedio":911.6243,"fechaActualizacion":"2026-11-13T00:00:00-04:00"}
JSON
cat > "$WORK/usd-fallback.json" <<'JSON'
[
  {"moneda":"USD","fuente":"oficial","nombre":"Dólar","compra":null,"venta":1234.5,
   "promedio":null,"fechaActualizacion":"2026-11-13T00:00:00-04:00"},
  {"moneda":"USD","fuente":"paralelo","nombre":"Paralelo","compra":900.25,"venta":null,
   "promedio":null,"fechaActualizacion":"2026-11-13T13:00:57.677Z"}
]
JSON
cat > "$WORK/usd-no-official.json" <<'JSON'
[
  {"moneda":"USD","fuente":"paralelo","nombre":"Paralelo","compra":null,"venta":null,
   "promedio":1070.339837,"fechaActualizacion":"2026-11-13T13:00:57.677Z"}
]
JSON
printf '[]\n' > "$WORK/eur-empty.json"

# ---- 1. the pill plus every published rate in the tooltip ---------------------------------------
fresh_cache 1
export USD_FIXTURE="$WORK/usd.json" EUR_FIXTURE="$WORK/eur.json" \
       OFFICIAL_FIXTURE="$WORK/official.json" CURL_FAIL=0
out="$(run)"
[ "$(field "$out" text)" = 'BCV Bs. 911,62' ] \
  && _ok 'official rate renders as "BCV Bs. 911,62"' \
  || _no "unexpected text: $(field "$out" text)"
tip="$(field "$out" tooltip)"
case "$tip" in
  *"Dólar oficial (BCV): Bs. 911,62"*) _ok 'tooltip lists the official dollar' ;;
  *) _no "tooltip lost the official dollar: $tip" ;;
esac
case "$tip" in
  *"Dólar paralelo: Bs. 1.070,34"*) _ok 'tooltip lists the parallel dollar' ;;
  *) _no "tooltip lost the parallel dollar: $tip" ;;
esac
case "$tip" in
  *"Euro oficial (BCV): Bs. 1.009,34"*) _ok 'tooltip lists the official euro' ;;
  *) _no "tooltip lost the official euro: $tip" ;;
esac
case "$tip" in
  *"Euro paralelo: Bs. 1.181,24"*) _ok 'tooltip lists the parallel euro' ;;
  *) _no "tooltip lost the parallel euro: $tip" ;;
esac
case "$tip" in
  *"BCV actualizado: 13/11/2026 00:00"*) _ok 'tooltip carries the BCV update time' ;;
  *) _no "tooltip lost the update time: $tip" ;;
esac

# ---- 2. null promedio falls back to venta/compra, with es-VE thousands ---------------------------
fresh_cache 2
export USD_FIXTURE="$WORK/usd-fallback.json" EUR_FIXTURE="$WORK/eur-empty.json"
out="$(run)"
[ "$(field "$out" text)" = 'BCV Bs. 1.234,50' ] \
  && _ok 'official fallback uses venta and es-VE thousands' \
  || _no "official fallback formatted wrong: $(field "$out" text)"
case "$(field "$out" tooltip)" in
  *"Dólar paralelo: Bs. 900,25"*) _ok 'parallel fallback uses compra' ;;
  *) _no "parallel fallback missing: $(field "$out" tooltip)" ;;
esac

# ---- 3. a fresh cache short-circuits BEFORE the network -----------------------------------------
rm -f "$CURL_LOG"
export CURL_FAIL=1
out="$(run)"
[ ! -f "$CURL_LOG" ] \
  && _ok 'fresh cache avoids the API entirely' \
  || _no 'a fresh cache still called curl'
[ "$(field "$out" text)" = 'BCV Bs. 1.234,50' ] \
  && _ok 'fresh cache returns the stored pill' \
  || _no "fresh cache returned: $(field "$out" text)"

# ---- 4. a stale cache is served when the API is down; the official endpoint is retried too ------
touch -d '2 hours ago' "$XDG_CACHE_HOME/archfrican/bcv.json"
rm -f "$CURL_LOG"
out="$(run)"
[ -f "$CURL_LOG" ] \
  && _ok 'stale cache retries the API' \
  || _no 'stale cache never retried the API'
[ "$(field "$out" text)" = 'BCV Bs. 1.234,50' ] \
  && _ok 'API outage keeps the last known rates visible' \
  || _no "API outage lost the cached rates: $(field "$out" text)"

# ---- 5. a payload without the official rate never overwrites the cache or crashes ---------------
fresh_cache 5
export USD_FIXTURE="$WORK/usd-no-official.json" EUR_FIXTURE="$WORK/eur.json" CURL_FAIL=0
out="$(run)"; rc=$?
[ "$rc" -eq 0 ] && [ "$(field "$out" text)" = '' ] \
  && _ok 'a payload without the official rate exits 0 and hides' \
  || _no "official-rate-less payload: rc=$rc out=$out"
[ ! -f "$XDG_CACHE_HOME/archfrican/bcv.json" ] \
  && _ok 'a payload without the official rate is not cached' \
  || _no 'an official-rate-less payload poisoned the cache'

# ---- 6. no cache and no network hides cleanly ---------------------------------------------------
fresh_cache 6
export CURL_FAIL=1
out="$(run)"; rc=$?
[ "$rc" -eq 0 ] && [ "$(field "$out" class)" = 'hidden' ] \
  && _ok 'offline with no cache hides cleanly' \
  || _no "offline/no-cache: rc=$rc out=$out"
[ ! -f "$XDG_CACHE_HOME/archfrican/bcv.json" ] \
  && _ok 'offline with no cache writes nothing' \
  || _no 'offline with no cache wrote a cache file'

# ---- 7. click mode puts every rate in a notification --------------------------------------------
fresh_cache 7
export USD_FIXTURE="$WORK/usd.json" EUR_FIXTURE="$WORK/eur.json" CURL_FAIL=0
run >/dev/null
rm -f "$CURL_LOG" "$NOTIFY_LOG"
run show >/dev/null
if [ -f "$NOTIFY_LOG" ] \
   && grep -q 'Dólar paralelo: Bs. 1.070,34' "$NOTIFY_LOG" \
   && grep -q 'Euro paralelo: Bs. 1.181,24' "$NOTIFY_LOG"; then
  _ok 'click notification lists the parallel dollar and euro'
else
  _no "click notification missing rates: $(cat "$NOTIFY_LOG" 2>/dev/null || echo '<none>')"
fi
[ ! -f "$CURL_LOG" ] \
  && _ok 'click with a fresh cache does not call the API' \
  || _no 'click with a fresh cache still called curl'

printf '\n  %d passed, %d failed\n' "$P" "$F"
[ "$F" -eq 0 ]
