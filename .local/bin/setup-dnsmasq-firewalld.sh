#!/usr/bin/env bash
set -euo pipefail

zone=${1:-internal}

sudo firewall-cmd --zone="${zone}" --permanent --add-service=dns
sudo firewall-cmd --zone="${zone}" --permanent --add-service=dhcp
sudo firewall-cmd --zone="${zone}" --permanent --add-service=tftp
sudo firewall-cmd --zone="${zone}" --permanent --add-port=8000/tcp

sudo firewall-cmd --reload
