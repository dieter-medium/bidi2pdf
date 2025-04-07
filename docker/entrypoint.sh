#!/bin/bash

USER_DATA_DIR=/home/appuser/.cache
mkdir -p ${USER_DATA_DIR}

/home/appuser/.webdrivers/chromedriver --port=${CHROMEDRIVER_PORT} \
                                       --headless \
                                       --whitelisted-ips="" \
                                       --allowed-origins="*" \
                                       --disable-dev-shm-usage \
                                       --disable-gpu \
                                       --user-data-dir=${USER_DATA_DIR} \
                                       --verbose