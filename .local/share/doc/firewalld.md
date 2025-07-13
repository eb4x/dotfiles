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

Sometimes you just want to block a whole country, other times you might want to
allow traffic from just one country.

```sh
curl -L https://www.ipdeny.com/ipblocks/data/aggregated/no-aggregated.zone -o no-aggregated.zone

firewall-cmd --permanent --new-ipset=norway --type=hash:net --option=family=inet
firewall-cmd --permanent --ipset=norway --add-entries-from-file=./no-aggregated.zone

firewall-cmd --permanent --zone=external --add-source=ipset:norway

firewall-cmd --premanent --zone=internal --add-source=10.0.0.0/8
firewall-cmd --premanent --zone=internal --add-source=172.16.0.0/12
firewall-cmd --premanent --zone=internal --add-source=192.168.0.0/16

firewall-cmd --permanent --zone=drop --add-source=ipset:china
# or
nmcli connection modify eno1 connection.zone drop

firewall-cmd --reload
```

# Polkit
AlmaLinux doesn't come with this one, so we'll just steal it from Fedora
`/usr/share/polkit-1/rules.d/org.fedoraproject.FirewallD1.rules` and modify it
to our own policy under `/etc/polkit-1/rules.d/org.fedoraproject.FirewallD1.rules`

The original checked for `subject.local` which prevens this rule from applying to
ssh sessions. I'm not sure we need anything other than `org.fedoraproject.FirewallD1.config`,
but lets leave the rest for completeness sake.

```javascript
polkit.addRule(function(action, subject) {
    if ((action.id == "org.fedoraproject.FirewallD1.config" ||
         action.id == "org.fedoraproject.FirewallD1.direct" ||
         action.id == "org.fedoraproject.FirewallD1.ipset"  ||
         action.id == "org.fedoraproject.FirewallD1.policy" ||
         action.id == "org.fedoraproject.FirewallD1.zone")  &&
         subject.active == true && subject.isInGroup("wheel")) {
         return polkit.Result.YES;
    }
});
```
