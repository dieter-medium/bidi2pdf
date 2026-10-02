#!/bin/bash
# Restarts the chromedriver container when Chrome is in a state it does not recover from by itself:
# chromedriver no longer answers /status, or the container's memory is thrashing (PSI "full" - every
# task stalled on memory for that share of the last 10 s). It stops chromedriver, entrypoint.sh
# exits, and the container's restart policy (unless-stopped, also Kamal's for accessories) starts a
# fresh one. Docker itself never restarts a merely "unhealthy" container. Renders still running on
# that Chrome fail - the client's retry and sweeper handle that.
#
# Opt-in: entrypoint.sh starts it when WATCHDOG_ENABLED=true.
# Usage: chromedriver-watchdog.sh <chromedriver pid>
#
#   WATCHDOG_INTERVAL         seconds between checks                 (default 15)
#   WATCHDOG_FAILURES         failed checks in a row before restart  (default 3)
#   WATCHDOG_STATUS_TIMEOUT   seconds /status may take               (default 5)
#   WATCHDOG_MEMORY_PRESSURE  PSI full avg10 percent that fails a check, 0 = off (default 50)
#   WATCHDOG_PRESSURE_FILE    the cgroup's PSI file (default /sys/fs/cgroup/memory.pressure)
set -euo pipefail

pid="${1:-}"
port="${CHROMEDRIVER_PORT:-3000}"
interval="${WATCHDOG_INTERVAL:-15}"
failures="${WATCHDOG_FAILURES:-3}"
status_timeout="${WATCHDOG_STATUS_TIMEOUT:-5}"
pressure_limit="${WATCHDOG_MEMORY_PRESSURE:-50}"
pressure_file="${WATCHDOG_PRESSURE_FILE:-/sys/fs/cgroup/memory.pressure}"
reason=""

log() {
  printf 'chromedriver-watchdog: %s\n' "$*" >&2
}

# Fails closed on a malformed setting: the watchdog does not start (chromedriver keeps running).
require_integer() {
  local name="$1" value="$2" min="$3"
  case "$value" in
    '' | *[!0-9]*)
      log "error: ${name} must be an integer >= ${min}, got '${value}' - not watching"
      exit 1
      ;;
  esac
  if ((10#$value < min)); then
    log "error: ${name} must be an integer >= ${min}, got '${value}' - not watching"
    exit 1
  fi
}

require_integer "chromedriver pid" "$pid" 1
require_integer CHROMEDRIVER_PORT "$port" 1
require_integer WATCHDOG_INTERVAL "$interval" 1
require_integer WATCHDOG_FAILURES "$failures" 1
require_integer WATCHDOG_STATUS_TIMEOUT "$status_timeout" 1
require_integer WATCHDOG_MEMORY_PRESSURE "$pressure_limit" 0

# Whole percent of the last 10 s in which every task of this cgroup stalled on memory; 0 when the
# kernel offers no PSI file (cgroup v1, PSI disabled).
memory_pressure() {
  if [[ ! -r "$pressure_file" ]]; then
    printf '0\n'
    return
  fi
  awk '$1 == "full" { split($2, kv, "="); printf "%d\n", kv[2]; found = 1 } END { if (!found) print 0 }' "$pressure_file"
}

check() {
  local pressure
  if ! curl -fs -m "$status_timeout" -o /dev/null "http://127.0.0.1:${port}/status"; then
    reason="chromedriver did not answer /status within ${status_timeout}s"
    return 1
  fi
  if ((pressure_limit > 0)); then
    pressure="$(memory_pressure)"
    if ((pressure >= pressure_limit)); then
      reason="memory pressure ${pressure}% (full avg10), limit ${pressure_limit}%"
      return 1
    fi
  fi
}

restart() {
  log "restarting: stopping chromedriver (pid ${pid}) so the container exits and its restart policy starts a fresh one"
  kill -TERM "$pid" 2>/dev/null || true
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    kill -0 "$pid" 2>/dev/null || exit 0
    sleep 1
  done
  kill -KILL "$pid" 2>/dev/null || true
  exit 0
}

log "watching chromedriver (pid ${pid}) every ${interval}s, restart after ${failures} failed checks"
failed=0
while kill -0 "$pid" 2>/dev/null; do
  sleep "$interval"
  if check; then
    failed=0
    continue
  fi
  failed=$((failed + 1))
  log "check ${failed}/${failures} failed: ${reason}"
  if ((failed >= failures)); then
    restart
  fi
done
