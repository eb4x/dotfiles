#!/usr/bin/env bash

# This is a script for creating an udev rule to put the predictable name wlan0
# for the otherwise horrible names wifi interfaces end up getting these days.

# And we do the rules based on pci location, because of the security feature of
# randomizing mac-addresses for wifi connections.

for interface in $(ls /sys/class/net); do

  if [ -f /etc/udev/rules.d/70-persistent-net.rules ]; then
    if grep -q wlan0 /etc/udev/rules.d/70-persistent-net.rules; then
      echo "Rule for wlan0 exists. Our work here is done."

      # Determine if script has been sourced
      if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
        return 0
      fi

      exit 0
    fi
  fi

  # Determine if we can figure something out about this
  # network interface

  if [ ! -f "/sys/class/net/${interface}/device/class" ]; then
    continue
  fi

  # All my wifi-nics have had class 0x028000 so far,
  # so if they don't, we're not interested in them.

  if [ "$(cat /sys/class/net/${interface}/device/class)" != "0x028000" ]; then
    continue
  fi

  # Examples of paths
  # /devices/pci0000:00/0000:00:14.3/net/wls5f3
  # /devices/pci0000:00/0000:00:14.3/net/wlp0s20f3
  # /devices/pci0000:00/0000:00:1c.2/0000:04:00.0/net/wlp4s0
  # /devices/pci0000:00/0000:00:1c.5/0000:3a:00.0/net/wlp58s0

  # Regex explanation
  # sed needs to escape (, ) and +
  # /devices/.*/   # Capture as much of the start of the path with .* (giving back as necessary)
  # (              #
  #    [^/]+       # Capture all characters not apart of a path separator preceeding
  # )              #
  # /net/interface # /net/<interface>
  #
  # Since we are only interested in the last part of the pci address

  pci_path=$(udevadm info -q path /sys/class/net/${interface} | sed 's /devices/.*/\([^/]\+\)/net/'${interface}' \1 g')

  # https://packetpushers.net/blog/udev/
  # This great article points to a command
  # `udevadm test-builtin net_id /sys/class/net/${interface}`
  # which output a line
  # `Parsing slot information from PCI device sysname "<pci_path_we_are_looking_for>"`,
  # So there's probably a cleaner way to do this.

  echo "SUBSYSTEM==\"net\", ACTION==\"add\", KERNELS==\"${pci_path}\", NAME=\"wlan0\"" | \
    sudo tee -a /etc/udev/rules.d/70-persistent-net.rules > /dev/null

  echo "Created rule for: ${interface} on ${pci_path}"
done
