# NAT

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

# IP Blocking

https://www.ipdeny.com/ipblocks/

Sometimes you just want to block a whole country, other times you might want to allow
traffic from just one country.

```sh
curl -L https://www.ipdeny.com/ipblocks/data/aggregated/no-aggregated.zone -o no-aggregated.zone

firewall-cmd --permanent --new-ipset=norway --type=hash:net --option=family=inet
firewall-cmd --permanent --ipset=norway --add-entries-from-file=./no-aggregated.zone

firewall-cmd --permanent --zone=external --add-source=ipset:norway
firewall-cmd --permanent --zone=external --add-rich-rule='rule family="ipv4" source not ipset="norway" drop'

firewall-cmd --reload
```
