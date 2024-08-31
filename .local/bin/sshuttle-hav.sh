#!/usr/bin/env bash

sshuttle --daemon \
  --pidfile /home/erikberg/sshuttle-hav.pid \
  --remote famous-koi 192.168.121.0/24
