#!/usr/bin/env bash

CIDRs="172.28.4.0/23"

if ! [[ $(hostname -I) =~ 129\.240\. ]]; then
  CIDRs="129.240.0.0/16 2001:700::/32 $CIDRs"
fi

sshuttle --daemon \
  --pidfile ${HOME}/sshuttle-uio.pid \
  --remote login.uio.no $CIDRs
