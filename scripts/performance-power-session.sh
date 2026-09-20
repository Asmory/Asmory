#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
usage:
  performance-power-session.sh status [--cpu N]
  performance-power-session.sh run --cpu N -- COMMAND [ARGS...]

Policy:
  supported host -> switch to performance -> verify -> run -> restore
  supported but transition fails -> hard error
  no supported control interface -> compatibility fallback
EOF
}

mode="${1:-}"
[[ -n "$mode" ]] || { usage >&2; exit 2; }
shift

cpu=""
if [[ "${1:-}" == "--cpu" ]]; then
  cpu="${2:-}"
  shift 2
fi

if [[ -z "$cpu" ]]; then
  allowed="$(awk '/^Cpus_allowed_list:/{sub(/^[^:]*:[[:space:]]*/,"");print;exit}' /proc/self/status 2>/dev/null || true)"
  first="${allowed%%,*}"
  cpu="${first%%-*}"
fi
[[ "$cpu" =~ ^[0-9]+$ ]] || { echo "cannot determine benchmark CPU" >&2; exit 2; }

base="/sys/devices/system/cpu/cpu${cpu}/cpufreq"
gov_file="$base/scaling_governor"
gov_avail="$base/scaling_available_governors"
epp_file="$base/energy_performance_preference"
epp_avail="$base/energy_performance_available_preferences"
driver_file="$base/scaling_driver"

read_trim() {
  local f="$1"
  [[ -r "$f" ]] || return 1
  tr -d '\n\r' < "$f" | xargs
}

has_word() {
  local needle="$1" hay="$2"
  [[ " $hay " == *" $needle "* ]]
}

write_sysfs() {
  local value="$1" file="$2"
  if [[ -w "$file" ]]; then
    printf '%s\n' "$value" > "$file"
    return 0
  fi
  if command -v sudo >/dev/null 2>&1; then
    printf '%s\n' "$value" | sudo tee "$file" >/dev/null
    return 0
  fi
  return 1
}

driver="$(read_trim "$driver_file" 2>/dev/null || echo unknown)"

ppd_supported=0
ppd_original="unavailable"
if command -v powerprofilesctl >/dev/null 2>&1; then
  if ppd_original="$(powerprofilesctl get 2>/dev/null)" && [[ -n "$ppd_original" ]]; then
    ppd_original="$(xargs <<<"$ppd_original")"
    if powerprofilesctl list 2>/dev/null | grep -q 'performance'; then
      ppd_supported=1
    fi
  fi
fi

gov_supported=0
gov_original="unavailable"
if [[ -r "$gov_file" ]]; then
  gov_original="$(read_trim "$gov_file")"
  avail="$(read_trim "$gov_avail" 2>/dev/null || true)"
  if [[ -z "$avail" ]] || has_word performance "$avail"; then
    gov_supported=1
  fi
fi

epp_supported=0
epp_original="unavailable"
if [[ -r "$epp_file" ]]; then
  epp_original="$(read_trim "$epp_file")"
  avail="$(read_trim "$epp_avail" 2>/dev/null || true)"
  if [[ -z "$avail" ]] || has_word performance "$avail"; then
    epp_supported=1
  fi
fi

supported=0
(( ppd_supported )) && supported=1
(( gov_supported )) && supported=1
(( epp_supported )) && supported=1

json_line() {
  local p="$1" g="$2" e="$3" managed="$4" fallback="$5"
  printf '{"schema":"asmory-power-session-v1","cpu":%s,"driver":"%s","managed":%s,"compatibility_fallback":%s,"required_mode":"performance","profile":"%s","governor":"%s","epp":"%s"}\n' \
    "$cpu" "$driver" "$managed" "$fallback" "$p" "$g" "$e"
}

show_status() {
  local p g e
  p="$ppd_original"
  if (( ppd_supported )); then
    p="$(powerprofilesctl get 2>/dev/null | xargs)"
  fi
  g="$(read_trim "$gov_file" 2>/dev/null || echo unavailable)"
  e="$(read_trim "$epp_file" 2>/dev/null || echo unavailable)"

  echo "Asmory performance power session"
  echo "  cpu:          $cpu"
  echo "  driver:       $driver"
  echo "  profile:      $p"
  echo "  governor:     $g"
  echo "  epp:          $e"
  if (( supported )); then
    echo "  compatible:   yes"
    echo "  benchmark:    switch -> verify -> restore"
  else
    echo "  compatible:   no supported control interface"
    echo "  benchmark:    compatibility fallback only"
  fi
}

if [[ "$mode" == "status" ]]; then
  show_status
  exit 0
fi

[[ "$mode" == "run" ]] || { usage >&2; exit 2; }
[[ "${1:-}" == "--" ]] || { usage >&2; exit 2; }
shift
(($#)) || { echo "missing command" >&2; exit 2; }

# Genuine host incompatibility: permit a marked local fallback.
if (( ! supported )); then
  meta="$(json_line unavailable unavailable unavailable false true)"
  echo "Asmory power session: unsupported host controls; compatibility fallback" >&2
  ASMORY_POWER_SESSION_JSON="$meta" "$@"
  exit $?
fi

changed_ppd=0
changed_gov=0
changed_epp=0

restore() {
  local failed=0
  if (( changed_epp )); then
    write_sysfs "$epp_original" "$epp_file" || failed=1
  fi
  if (( changed_gov )); then
    write_sysfs "$gov_original" "$gov_file" || failed=1
  fi
  if (( changed_ppd )); then
    powerprofilesctl set "$ppd_original" >/dev/null 2>&1 || failed=1
  fi
  (( failed == 0 ))
}

trap 'restore || true' EXIT INT TERM

# Supported interface failure is a hard error, not a compatibility fallback.
if (( ppd_supported )); then
  current="$(powerprofilesctl get 2>/dev/null | xargs)"
  if [[ "$current" != "performance" ]]; then
    echo "Asmory: power profile $current -> performance" >&2
    powerprofilesctl set performance >/dev/null || {
      echo "supported power-profile transition failed" >&2
      exit 4
    }
    changed_ppd=1
  fi
fi

if (( gov_supported )); then
  current="$(read_trim "$gov_file")"
  if [[ "$current" != "performance" ]]; then
    echo "Asmory: cpu$cpu governor $current -> performance" >&2
    write_sysfs performance "$gov_file" || {
      echo "supported governor transition failed" >&2
      exit 4
    }
    changed_gov=1
  fi
fi

if (( epp_supported )); then
  current="$(read_trim "$epp_file")"
  if [[ "$current" != "performance" ]]; then
    echo "Asmory: cpu$cpu EPP $current -> performance" >&2
    write_sysfs performance "$epp_file" || {
      echo "supported EPP transition failed" >&2
      exit 4
    }
    changed_epp=1
  fi
fi

active_p="unavailable"
active_g="unavailable"
active_e="unavailable"

if (( ppd_supported )); then
  active_p="$(powerprofilesctl get 2>/dev/null | xargs)"
  [[ "$active_p" == "performance" ]] || { echo "power profile verification failed" >&2; exit 5; }
fi
if (( gov_supported )); then
  active_g="$(read_trim "$gov_file")"
  [[ "$active_g" == "performance" ]] || { echo "governor verification failed" >&2; exit 5; }
fi
if (( epp_supported )); then
  active_e="$(read_trim "$epp_file")"
  [[ "$active_e" == "performance" ]] || { echo "EPP verification failed" >&2; exit 5; }
fi

meta="$(json_line "$active_p" "$active_g" "$active_e" true false)"
echo "Asmory power session: performance verified on cpu$cpu" >&2

set +e
ASMORY_POWER_SESSION_JSON="$meta" "$@"
cmd_rc=$?
set -e

restore_rc=0
restore || restore_rc=$?
trap - EXIT INT TERM

if (( restore_rc )); then
  echo "failed to fully restore original power policy" >&2
  exit 6
fi

exit "$cmd_rc"
