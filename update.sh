#!/bin/bash

sort -u -o config/gw.conf config/gw.conf
sort -u -o config/ad.conf config/ad.conf
sort -u -o config/ad_blank.conf config/ad_blank.conf

mkdir tmp
cd tmp

# Put cn ip range to ipset conf that from apnic
wget -O apnic https://ftp.apnic.net/apnic/stats/apnic/delegated-apnic-latest
echo "create cn hash:net family inet hashsize 1024 maxelem 65536" > ../cn.ips
cat apnic | awk -F\| '/CN\|ipv4/ { printf("add cn %s/%d\n", $4, 32-log($5)/log(2)) }' >> ../cn.ips

# gw
wget -O gw.tmp https://cokebar.github.io/gfwlist2dnsmasq/gfwlist_domain.txt

# extend to top domain
# cat gw | awk -F. '{if ($(NF-1) ~ /^(com|org|net|gov|edu|info|co|in)$/ && NF>2) print $(NF-2)"."$(NF-1)"."$(NF); else print $(NF-1)"."$(NF)}' > gw.tmp

# Add custom domain
cat ../config/gw.conf >> gw.tmp

# Uniq and sort gw list
sort -u -o gw gw.tmp

# Put anti-ad to ad
wget -O anti https://raw.githubusercontent.com/privacy-protection-tools/anti-AD/master/adblock-for-dnsmasq.conf
cat anti | grep address=/|awk -F/ '{print $2}' > ad
# Add custom ad hosts
cat ../config/ad.conf >> ad
# Remove the first dot ex: .abc.com
sed -i.bak 's/^\.//g' ad
rm ad.bak

# Uniq and sort ad list
sort -u -o ad ad

# Allow ad in blank list
comm -2 -3 ad ../config/ad_blank.conf > ad.tmp
rm ad && mv ad.tmp ad

# Generate ad.hosts file for dnsmasq
# awk '{print "0.0.0.0 "$0}' ad > ../ad.hosts
awk '{print "address=/"$0"/"}' ad > ../ad.hosts

# Generate gw.hosts file for dnsmasq
awk '{print "server=/"$0"/127.0.0.1#1053"}' gw > ../gw.hosts
awk '{print "ipset=/"$0"/gw"}' gw >> ../gw.hosts
awk '{print "server=/"$0"/8.8.8.8"}' gw > ../gw-udp.hosts
awk '{print "ipset=/"$0"/gw"}' gw >> ../gw-udp.hosts

cd ..
rm -rf tmp
