#!/usr/bin/env bash

sshuttle --daemon \
  --pidfile ${HOME}/sshuttle-uio.pid \
  --remote login.uio.no 129.240.0.0/16 172.28.4.0/23
