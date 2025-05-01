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
  xauth generate :99 . trusted

  umask $old_umask

  export XAUTHORITY=/home/appuser/.Xauthority

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
  x11vnc -storepasswd $VNC_PASS /home/appuser/.vnc/passwd
  umask $old_umask
  x11vnc -display WAIT:99 -xkb -noxrecord -noxfixes -noxdamage -forever -usepw -create -rfbauth /home/appuser/.vnc/passwd &
fi

# DISPLAY=:99 /home/appuser/.webdrivers/chromedriver --port=33259 --whitelisted-ips=""  --allowed-origins="*" --disable-dev-shm-usage --disable-gpu  --verbose
/home/appuser/.webdrivers/chromedriver --port=${CHROMEDRIVER_PORT} \
                                       --headless \
                                       --whitelisted-ips="" \
                                       --allowed-origins="*" \
                                       --disable-dev-shm-usage \
                                       --disable-gpu \
                                       --user-data-dir=${USER_DATA_DIR} \
                                       --verbose