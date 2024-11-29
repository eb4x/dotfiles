#!/usr/bin/env bash

if [ ! -f $HOME/.config/hypr/hostname.conf ]; then
  echo "\$hostname = $(hostname --short)" > $HOME/.config/hypr/hostname.conf
fi
