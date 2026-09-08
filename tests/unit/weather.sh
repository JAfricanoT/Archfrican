#!/usr/bin/env bash
# Unit test for home/dot_local/bin/executable_archfrican-weather's city resolution.
#
# Black-box: invokes the real script as a subprocess against a fake HOME and a stub curl, so no test
# ever touches the network. The stub records the URL it was asked for and returns a minimal but valid
# wttr.in j1 payload, which makes the URL itself the assertable output — and the URL is precisely
# where this script's only interesting logic lands (config file → city name → query encoding).
#
# Regression covered: the config-file branch used `tr -d '[:space:]'`, which deletes a city's INTERNAL
# spaces, not just the trailing newline it meant to strip. "New York" became "NewYork", which wttr.in
# happily resolves to East Kamias, Philippines — a wrong answer delivered with total confidence, and
# for a spelling the script's own usage comment documents as supported.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT="$(cd -- "$HERE/../.." && pwd)"
SCRIPT="$ROOT/home/dot_local/bin/executable_archfrican-weather"

P=0; F=0
_ok(){ printf '  \033[32mok\033[0m   %s\n' "$1"; P=$((P + 1)); }
_no(){ printf '  \033[31mFAIL\033[0m %s\n' "$1"; F=$((F + 1)); }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
export HOME="$WORK/home"
export XDG_CONFIG_HOME="$HOME/.config"
mkdir -p "$XDG_CONFIG_HOME/archfrican" "$WORK/fakebin"

# Stub curl: record the URL, emit a valid j1 body. Every field the script's python reader touches is
# present, so a parse error in the test means a real regression rather than a thin fixture.
cat > "$WORK/fakebin/curl" <<'STUB'
#!/bin/sh
for a in "$@"; do
  case "$a" in https://*) printf '%s\n' "$a" > "$WORK_URL" ;; esac
done
cat <<'JSON'
{"current_condition":[{"temp_C":"29","FeelsLikeC":"31","humidity":"65",
  "weatherDesc":[{"value":"Overcast"}]}],
 "nearest_area":[{"areaName":[{"value":"Valencia"}],"country":[{"value":"Venezuela"}]}]}
JSON
STUB
chmod +x "$WORK/fakebin/curl"
export WORK_URL="$WORK/last-url"
export PATH="$WORK/fakebin:$PATH"

# Each case runs against a COLD cache: the script short-circuits on a cache younger than 30 min, so a
# shared cache dir would make every case after the first assert on the first case's query.
run_with_city() {
  printf '%s' "$1" > "$XDG_CONFIG_HOME/archfrican/weather"
  export XDG_CACHE_HOME="$WORK/cache-$2"
  rm -f "$WORK_URL"
  bash "$SCRIPT" >/dev/null 2>&1
  cat "$WORK_URL" 2>/dev/null
}

# ---- 1. multi-word city keeps its word boundary --------------------------------------------------
url="$(run_with_city 'Buenos Aires' 1)"
case "$url" in
  *"Buenos+Aires"*) _ok 'multi-word city encodes as "Buenos+Aires"' ;;
  *"BuenosAires"*)  _no 'internal space DELETED — "Buenos Aires" collapsed to "BuenosAires"' ;;
  *)                _no "unexpected query URL: ${url:-<none>}" ;;
esac

# ---- 2. the exact wrong-continent case: "New York" must not become "NewYork" ----------------------
url="$(run_with_city 'New York' 2)"
case "$url" in
  *"New+York"*) _ok '"New York" survives as a two-word query' ;;
  *)            _no "\"New York\" mangled into: ${url:-<none>}" ;;
esac

# ---- 3. a trailing newline IS still stripped (the thing tr -d was there for) ----------------------
printf 'Lisbon\n' > "$XDG_CONFIG_HOME/archfrican/weather"
export XDG_CACHE_HOME="$WORK/cache-3"; rm -f "$WORK_URL"
bash "$SCRIPT" >/dev/null 2>&1
url="$(cat "$WORK_URL" 2>/dev/null)"
case "$url" in
  *"Lisbon?"*) _ok 'trailing newline stripped from city name' ;;
  *)           _no "trailing whitespace leaked into query: ${url:-<none>}" ;;
esac

# ---- 4. surrounding spaces trimmed, inner comma+space preserved -----------------------------------
url="$(run_with_city '  Valencia, Venezuela  ' 4)"
case "$url" in
  *"Valencia,+Venezuela"*) _ok 'qualified city trims outside, keeps inside' ;;
  *)                       _no "qualified city mangled into: ${url:-<none>}" ;;
esac

# ---- 5. "off" still hides the module (and never queries) ------------------------------------------
export XDG_CACHE_HOME="$WORK/cache-5"; rm -f "$WORK_URL"
printf 'off\n' > "$XDG_CONFIG_HOME/archfrican/weather"
out="$(bash "$SCRIPT" 2>/dev/null)"
if printf '%s' "$out" | grep -q '"class":"hidden"' && [ ! -f "$WORK_URL" ]; then
  _ok '"off" hides the module without querying'
else
  _no "\"off\" did not hide cleanly: $out"
fi

# ---- 6. an empty config falls back to auto, never to an empty query -------------------------------
# A bare https://wttr.in/?format=j1 makes wttr.in geolocate by exit IP, which on a VPN reports the
# tunnel's country. Asserting "some city is present" rather than a specific one keeps this portable
# to whatever timezone the CI runner is set to.
export XDG_CACHE_HOME="$WORK/cache-6"; rm -f "$WORK_URL"
printf '   \n' > "$XDG_CONFIG_HOME/archfrican/weather"
bash "$SCRIPT" >/dev/null 2>&1
url="$(cat "$WORK_URL" 2>/dev/null)"
case "$url" in
  "https://wttr.in/?format=j1") _no 'empty config produced an IP-geolocated query' ;;
  https://wttr.in/?*format=j1)  _ok 'empty config falls back to the timezone city' ;;
  *)                            _no "empty config produced no usable query: ${url:-<none>}" ;;
esac

printf '\n  %d passed, %d failed\n' "$P" "$F"
[ "$F" -eq 0 ]
