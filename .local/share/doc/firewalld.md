
```sh
nmcli connection modify eno1 connection.zone internal
nmcli connection reload

firewall-cmd --permanent --new-policy internal-to-public
firewall-cmd --permanent --policy=internal-to-public --set-target=ACCEPT
firewall-cmd --permanent --policy=internal-to-public --add-ingress-zone=internal
firewall-cmd --permanent --policy=internal-to-public --add-egress-zone=public
firewall-cmd --permanent --policy=internal-to-public --add-masquerade
firewall-cmd --reload
```
