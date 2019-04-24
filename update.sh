#!/bin/bash

mkdir tmp
cd tmp

wget -O sr.conf https://raw.githubusercontent.com/h2y/Shadowrocket-ADBlock-Rules/master/sr_top500_banlist_ad.conf

# gw
cat sr.conf | grep Proxy|grep DOMAIN-SUFFIX|awk -F, '{print $2}' > gw
# add custom domain
cat ../config/gw.conf >> gw

# Uniq and sort gw list
sort -u -o gw gw

# ad
cat sr.conf | grep Reject|grep DOMAIN-SUFFIX|awk -F, '{print $2}' > ad
# remove the first dot ex: .abc.com
sed -i.bak 's/^\.//g' ad
rm ad.bak
# add custom ad hosts
cat ../config/ad.conf >> ad

# Uniq and sort ad list
sort -u -o ad ad
sort -u -o ../config/ad_blank.conf ../config/ad_blank.conf

# Allow ad in blank list
comm -2 -3 ad ../config/ad_blank.conf > ad.tmp
rm ad && mv ad.tmp ad

# Export the mini version for gw
echo > gw-mini
cat gw | grep amazonaws >> gw-mini
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

# generate ad.hosts file for dnsmasq
sed 's/^/0.0.0.0 &/g' ad > ../ad.hosts

# generate auto.pac file for client
pac=auto.pac
echo 'var gwMap = {' > ../$pac
awk '{print "  \""$0"\": 1,"}' gw >> ../$pac
echo '}' >> ../$pac
cat ../config/auto.pac >> ../$pac

# generate auto-mini.pac file for client
pac=auto-mini.pac
echo 'var gwMap = {' > ../$pac
awk '{print "  \""$0"\": 1,"}' gw-mini >> ../$pac
echo '}' >> ../$pac
cat ../config/auto.pac >> ../$pac

cd ..
rm -rf tmp
