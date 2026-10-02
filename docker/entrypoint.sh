#!/bin/bash

USER_DATA_DIR=/home/appuser/.cache
mkdir -p ${USER_DATA_DIR}

if [ "$ENABLE_XVFB" = "true" ]; then
  rm -rf /tmp/.X99-lock

  export DISPLAY=:99
  Xvfb :99 -screen 0 1920x1080x24 &

  old_umask=$(umask)
  umask 077

  touch /home/appuser/.Xauthority
  export XAUTHORITY=/home/appuser/.Xauthority

  xauth generate :99 . trusted

  umask "$old_umask"



  until xdpyinfo -display ${DISPLAY} >/dev/null 2>&1; do
      sleep 0.2
  done

  fluxbox &

  until wmctrl -m > /dev/null 2>&1; do
    sleep 0.2
  done
fi

if [ "$ENABLE_VNC" = "true" ]; then
  VNC_PASS=${VNC_PASS:-$(tr -dc A-Za-z0-9 </dev/urandom | head -c 12)}
  echo "VNC password: $VNC_PASS"
  old_umask=$(umask)
  umask 077
  mkdir -p /home/appuser/.vnc
  x11vnc -storepasswd "$VNC_PASS" /home/appuser/.vnc/passwd
  umask "$old_umask"
  x11vnc -display WAIT:99 -xkb -noxrecord -noxfixes -noxdamage -forever -shared -noshm -usepw -rfbauth /home/appuser/.vnc/passwd &
fi

# DISPLAY=:99 /home/appuser/.webdrivers/chromedriver --port=33259 --whitelisted-ips=""  --allowed-origins="*" --disable-dev-shm-usage --disable-gpu  --verbose
/home/appuser/.webdrivers/chromedriver --port="${CHROMEDRIVER_PORT}" \
                                       --allowed-ips="" \
                                       --allowed-origins="*" \
                                       --disable-dev-shm-usage \
                                       --disable-gpu \
                                       --user-data-dir="${USER_DATA_DIR}" \
                                       --log-level="${CHROMEDRIVER_LOG_LEVEL:-INFO}" \
                                       --readable-timestamp &
chromedriver_pid=$!

# docker stop sends TERM to this script (PID 1): pass it on so chromedriver ends its sessions.
trap 'kill -TERM "$chromedriver_pid" 2>/dev/null' TERM INT

# Opt-in watchdog (see chromedriver-watchdog.sh): stops chromedriver when it no longer answers or
# memory thrashes, so this script exits and the restart policy starts a fresh container. It leaves
# a marker first, in a private temp dir, so the exit below is non-zero for any restart policy.
watchdog_marker=""
if [ "${WATCHDOG_ENABLED:-false}" = "true" ]; then
  if watchdog_dir="$(mktemp -d)"; then
    watchdog_marker="${watchdog_dir}/restarted"
  fi
  /usr/local/bin/chromedriver-watchdog.sh "$chromedriver_pid" "$watchdog_marker" &
fi

# A trapped signal interrupts wait before chromedriver has ended: wait again until it has.
status=0
wait "$chromedriver_pid" || status=$?
while kill -0 "$chromedriver_pid" 2>/dev/null; do
  status=0
  wait "$chromedriver_pid" || status=$?
done

if [ -n "$watchdog_marker" ] && [ -e "$watchdog_marker" ] && [ "$status" -eq 0 ]; then
  status=1
fi
exit "$status"
