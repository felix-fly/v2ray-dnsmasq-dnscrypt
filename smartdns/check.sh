#!/bin/sh

APP=/etc/smartdns/smartdns
CONF=/etc/smartdns/my.conf

NUM=`ps | grep -w $APP | grep -v grep | wc -l`
if [ "$NUM" -lt "1" ];then
  $APP -c $CONF
elif [ "$NUM" -gt "1" ];then
  pgrep -f $APP | xargs kill -9
  sleep 1s
  $APP -c $CONF
fi

exit 0
