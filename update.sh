#!/bin/bash

mkdir tmp
cd tmp

# Put cn ip range to ipset conf that from apnic
wget -O apnic https://ftp.apnic.net/apnic/stats/apnic/delegated-apnic-latest
echo "create cn hash:net family inet hashsize 1024 maxelem 65536" > ../cn.conf
cat apnic | awk -F\| '/CN\|ipv4/ { printf("add cn %s/%d\n", $4, 32-log($5)/log(2)) }' >> ../cn.conf

wget -O sr.conf https://raw.githubusercontent.com/h2y/Shadowrocket-ADBlock-Rules/master/sr_top500_banlist_ad.conf

# gw
cat sr.conf | grep Proxy|grep DOMAIN-SUFFIX|awk -F, '{print $2}' > gw
# Add custom domain
cat ../config/gw.conf >> gw

# Uniq and sort gw list
sort -u -o gw gw

# ad
cat sr.conf | grep Reject|grep DOMAIN-SUFFIX|awk -F, '{print $2}' > ad
# Another smaller ad hosts
wget -O hosts https://cdn.jsdelivr.net/gh/neoFelhz/neohosts@gh-pages/basic/hosts
sed -i.bak $'s/\r//g' hosts
cat hosts | grep 0.0.0.0|awk '{print $2}' >> ad
# Add custom ad hosts
cat ../config/ad.conf >> ad
# Remove the first dot ex: .abc.com
sed -i.bak 's/^\.//g' ad
rm ad.bak

# Uniq and sort ad list
sort -u -o ad ad
sort -u -o ../config/ad_blank.conf ../config/ad_blank.conf

# Allow ad in blank list
comm -2 -3 ad ../config/ad_blank.conf > ad.tmp
rm ad && mv ad.tmp ad

# Export the mini version for gw
cat gw | grep amazonaws > gw-mini
cat gw | grep google >> gw-mini
cat gw | grep blogspot >> gw-mini
cat gw | grep youtube >> gw-mini
cat gw | grep facebook >> gw-mini
cat gw | grep twitter >> gw-mini
cat gw | grep dropbox >> gw-mini
cat gw | grep github >> gw-mini
cat gw | grep v2ex >> gw-mini
cat gw | grep v2ray >> gw-mini
cat gw | grep cdn >> gw-mini
sort -u -o gw-mini gw-mini

# Generate ad.hosts file for dnsmasq
awk '{print "address=/"$0"/0.0.0.0"}' ad > ../ad.hosts

# Generate gw.hosts and gw-mini.hosts file for dnsmasq
awk '{print "server=/"$0"/127.0.0.1#1053"}' gw > ../gw.hosts
awk '{print "ipset=/"$0"/gw"}' gw >> ../gw.hosts
awk '{print "server=/"$0"/127.0.0.1#1053"}' gw-mini > ../gw-mini.hosts
awk '{print "ipset=/"$0"/gw"}' gw-mini >> ../gw-mini.hosts

cd ..
rm -rf tmp
