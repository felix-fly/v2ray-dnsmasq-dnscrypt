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

wget -O sr.conf https://raw.githubusercontent.com/h2y/Shadowrocket-ADBlock-Rules/master/sr_top500_banlist_ad.conf

# gw
cat sr.conf | grep Proxy|grep DOMAIN-SUFFIX|awk -F, '{print $2}' > gw.tmp
cat sr.conf | grep Proxy|grep IP-CIDR|awk -F, '{print $2}' > gw_ip
echo "create gw hash:net family inet hashsize 1024 maxelem 65536" > ../gw.ips
awk '{print "add gw "$0}' gw_ip >> ../gw.ips
# extend to top domain
# cat gw | awk -F. '{if ($(NF-1) ~ /^(com|org|net|gov|edu|info|co|in)$/ && NF>2) print $(NF-2)"."$(NF-1)"."$(NF); else print $(NF-1)"."$(NF)}' > gw.tmp
# Other popular sites
wget -O other.conf https://raw.githubusercontent.com/Hackl0us/SS-Rule-Snippet/master/%E8%A7%84%E5%88%99%E7%89%87%E6%AE%B5%E9%9B%86/%E8%87%AA%E9%80%89%E8%A7%84%E5%88%99%E9%9B%86/%E5%B8%B8%E8%A7%81%E5%9B%BD%E5%A4%96%E7%BD%91%E7%AB%99%E5%88%97%E8%A1%A8.txt
cat other.conf | grep Proxy|grep DOMAIN-SUFFIX|awk -F, '{print $2}' >> gw.tmp
# Add custom domain
cat ../config/gw.conf >> gw.tmp

# Uniq and sort gw list
sort -u -o gw gw.tmp

# ad
cat sr.conf | grep Reject|grep DOMAIN-SUFFIX|awk -F, '{print $2}' > ad
# Another smaller ad hosts
wget -O hosts https://cdn.jsdelivr.net/gh/neoFelhz/neohosts@gh-pages/basic/hosts
sed -i.bak $'s/\r//g' hosts
cat hosts | grep 0.0.0.0|awk '{print $2}' >> ad
# Put anti-ad to ad-ext
wget -O anti https://anti-ad.net/anti-ad-for-dnsmasq.conf
cat anti | grep address=/|awk -F/ '{print $2}' > ad-ext
# Add custom ad hosts
cat ../config/ad.conf >> ad
# Remove the first dot ex: .abc.com
sed -i.bak 's/^\.//g' ad
rm ad.bak
# ad ips
cat sr.conf | grep Reject|grep IP-CIDR|awk -F, '{print $2}' > ad_ip
echo "create ad hash:net family inet hashsize 1024 maxelem 65536" > ../ad.ips
awk '{print "add ad "$0}' ad_ip >> ../ad.ips

# Uniq and sort ad list
sort -u -o ad ad
sort -u -o ad-ext ad-ext

# Remove duplicate ad
comm -2 -3 ad-ext ad > ad-ext.tmp
rm ad-ext && mv ad-ext.tmp ad-ext

# Allow ad in blank list
comm -2 -3 ad ../config/ad_blank.conf > ad.tmp
rm ad && mv ad.tmp ad

# Generate ad.hosts file for dnsmasq
awk '{print "address=/"$0"/"}' ad > ../ad.hosts
awk '{print "address=/"$0"/"}' ad-ext > ../ad-ext.hosts

# Generate gw.hosts file for dnsmasq
awk '{print "server=/"$0"/127.0.0.1#1053"}' gw > ../gw.hosts
awk '{print "ipset=/"$0"/gw"}' gw >> ../gw.hosts
awk '{print "server=/"$0"/8.8.8.8"}' gw > ../gw-udp.hosts
awk '{print "ipset=/"$0"/gw"}' gw >> ../gw-udp.hosts

cd ..
rm -rf tmp
