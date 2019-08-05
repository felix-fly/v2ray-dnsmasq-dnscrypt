# v2ray-dnsmasq-doh

本文为在路由器openwrt中使用v2ray的另一种解决方案，之前相对简单的方案在这里[v2ray-openwrt](https://gitee.com/felix-fly/v2ray-openwrt)。重点说下本方案的不同或者特点：

* dnsmasq负责园内的解析（默认）
* dnsmasq直接屏蔽广告域名
* dns-over-https(doh)负责园外的解析（基于gw表或cn表）
* ipset记录园外域名的ip（gw模式下）
* iptables根据ipset转发指定流量到v2ray
* v2ray只负责进站出站

已经有了简单的v2ray全包方案，为什么还要这个看上去要复杂的多的方案？需求。是的。

如果简单方案你用下来没有感觉到有什么问题，可以不用再继续下去了，洗洗睡吧。

## 需求

下面来聊聊我的需求：

* 起因

  一直以来家里的主路由都是由k2p承担，刷padavan也很稳定，v2ray也一直默默的守护着，一切都很和谐。但是下载速度一直都不是很理想，离100m的标称带宽差距很悬殊，虽说网速不稳定但是不能一直这么低吧。有次下载时刚好登陆了路由看到cpu负载一直很高，下载完了才回复到正常水平。之前论坛就有人说v2ray比较吃性能，差的路由就不要折腾了。看来mt7621这个于v2ray而言应该是很差了（其实个人感觉还可以啊，不至于那么差啦）。

  于是又把吃灰的k3翻出来，就路由来说这个应该不差了吧，咱不能拿pc的来比是不。话说这k3之前被刷的没了5g Wi-Fi，虽然2.4g可以勉强用，但是心里总归不痛快，于是又google了一大圈，各种折腾，重置、刷机、各个版本。。。现在可以来总结下了，进cef恢复nvram可以解决大部分问题，还要一个要注意的是固件版本，现在openwrt官方的snapshot已经支持k3了，用openwrt官方固件的话，5g需要国家us，信道149然后重启就有5g信号了，这不知道是什么鬼，现在用lede的自编译固件，官方的没有那些定制软件，等它慢慢完善吧。

  刷好了固件，v2ray等等各种配置好，然后悄悄的替换下已不堪重负的k2p，开足马力下载。果不出其然，速度是上来了，但是还是没能跑满带宽，峰值也就8～9m的样子，赶快登上路由看看，cpu还是很高，看来k3在v2ray面前也只能惭愧的低下了原本高昂的头颅。

* 分析探索

  又翻了翻v2ray的文档、各种文章、论坛，也没什么收获，看来只能自己想办法了。那么就来分析一下，目前的方案所有的流量都进v2ray，然后由v2ray根据路由规则选择不同的出站口，这样一来v2ray就是一个中心节点，承担了全部的工作（兄弟，你辛苦了），小流量情况下完全ok，但是大流量时cpu就会上去。基于此，于是想把路由的这块任务分离出去，v2ray只负责单一的进站和出站，只有需要的流量才会进到v2ray，一般情况下的下载都是园内为主，所以这样可以大大的减轻v2ray的工作量。

## 新的方案

作战方针制定好了那就开始战略部署吧。早些年时候ss的解决方案正好可以参考，dnsmasq系列相关的教程多如牛毛。初版采用了dnsmasq+dnscrypt+ipset+iptables这一组合，使用一段时间后发现效果不好。由于提供dnscrypt解析的多为园外的服务器，解析速度不理想，很明显感觉网页打开缓慢，于是寻找新的方案。目前选择了dns-over-https这种，又名doh，具体是什么自行科普下。开始想自己搭建服务器，偶然发现红鱼已经有成熟的服务可用，尝试之后速度明显提升，不在卡白。openwrt安装也很简单，同样搜https_dns_proxy，个人觉得不用安装luci-app相关的，只要安装https_dns_proxy本身就可以了，luci那边界面配置没有自定义源，只有两个内置选项，用不起来。具体的使用后面说明。

### 下载hosts和ips文件

* [ad.hosts](./ad.hosts) # 屏蔽广告
* [gw.hosts](./gw.hosts) # 某个域名列表，用于gw模式
* [gw-mini.hosts](./gw-mini.hosts) # gw-mini是gw的子集，仅包含了常用的一些网站域名，可根据个人需求选择
* [cn.conf](./cn.conf) # 从apnic提取出来的ip段集合，用于cn模式（园内直连）

通过ssh上传的路由器，路径此处为
```base
/etc/config/v2ray/
```
你可以放到自己喜欢的路径下，注意与下面的dnsmasq.conf配置中保持一致即可。看到有人说可以开机自动复制到/tmp目录，然后dnsmasq从/tmp下读文件更快，/tmp路径实际是内存。

### dnsmasq配置

可以在luci界面进行配置，也可以直接在dnsmasq.conf文件里配置，luci界面的优先级更高，换句话说就是会覆盖dnsmasq.conf文件里相同的配置项。

```base
vi /etc/dnsmasq.conf
```
加入下面的配置项，使用cn模式的话，只需要ad.hosts文件即可
```base
conf-dir=/etc/config/v2ray, *.hosts
```
dnsmasq配置不正确可能会导致无法上网，这里修改完了可以用下面的命令测试一下
```base
dnsmasq -test
```

### dns-over-https配置

```base
vi /etc/config/https_dns_proxy
```
可以看到内置了google和couldflare两家的服务，但是由于众所周知的原因，可能不太好用，或者说不能用，修改成下面的，红鱼的地址填好，端口可以根据个人口味调整
```base
config https_dns_proxy
  option listen_addr '127.0.0.1'
  option listen_port '1053'
  option user 'nobody'
  option group 'nogroup'
  option subnet_addr ''
  option proxy_server ''
  option url_prefix 'https://dns.rubyfish.cn/dns-query?'
```

也可以在服务器上安装自己的doh服务，以下基于Ubuntu 18.04

```base
# install go
sudo apt install golang-go
# setup doh
git clone https://github.com/m13253/dns-over-https.git
cd dns-over-https
make
sudo make install
sudo systemctl start doh-server.service
sudo systemctl enable doh-server.service
```

doh的配置文件在这里，一般不用改动

```base
sudo vi /etc/dns-over-https/doh-server.conf
```

修改服务器上nginx的配置，添加

```base
location /dns-query {
  proxy_redirect off;
  proxy_set_header Host $http_host;
  proxy_pass http://127.0.0.1:8053/dns-query;
}
```

nginx需要对外提供https访问，相关教程很多，这里不再赘述。

### iptables规则

在 **luci-网络-防火墙-自定义规则** 下添加

#### gw模式

```base
ipset -N gw iphash
iptables -t nat -A PREROUTING -p tcp -m set --match-set gw dst -j REDIRECT --to-port 12345
```

#### cn模式
```base
ipset -R < /etc/config/v2ray/cn.conf

iptables -t nat -N V2RAY
iptables -t nat -A V2RAY -d 0.0.0.0 -j RETURN
iptables -t nat -A V2RAY -d 127.0.0.1 -j RETURN
iptables -t nat -A V2RAY -d 192.168.1.0/24 -j RETURN
iptables -t nat -A V2RAY -d YOUR_SERVER_IP -j RETURN
iptables -t nat -A V2RAY -m set --match-set cn dst -j RETURN
iptables -t nat -A V2RAY -p tcp -j REDIRECT --to-ports 12345
iptables -t nat -A PREROUTING -j V2RAY
```

cn模式需要将YOUR_SERVER_IP替换为实际的ip地址，局域网不是192.168.1.x段的根据实际情况修改。iptables配置要谨慎，错误的配置会造成无法连接路由器，只能重置路由器（恢复出厂设置）。

### v2ray配置

替换==包含的内容为你自己的配置

```json
{
  "log": {
    "error": "./error.log",
    "loglevel": "warning"
  },
  "inbounds": [{
    "port": 12345,
    "protocol": "dokodemo-door",
    "settings": {
      "network": "tcp,udp",
      "followRedirect": true
    }
  }],
  "outbounds": [{
    "protocol": "vmess",
    "tag": "proxy",
    "settings": {
      "vnext": [{
        "address": "==YOUR DOMAIN or SERVER ADDRESS==",
        "port": 443,
        "users": [{
          "id": "==YOUR USER ID==",
          "alterId": 128,
          "level": 1,
          "security": "chacha20-poly1305"
        }]
      }]
    },
    "streamSettings": {
      "network" : "ws",
      "security": "tls",
      "wsSettings": {
        "path": "/==YOUR ENTRY PATH==/"
      },
      "tlsSettings": {
        "serverName": "==YOUR DOMAIN or SERVER ADDRESS==",
        "allowInsecure": true
      }
    }
  }]
}
```

## 规则来源及更新

主要规则取自

* [https://github.com/h2y/Shadowrocket-ADBlock-Rules](https://github.com/h2y/Shadowrocket-ADBlock-Rules)
* [https://github.com/neoFelhz/neohosts](https://github.com/neoFelhz/neohosts)

生成的hosts文件不定期更新，你也可以clone到本地自己更新规则，或着fork一份做你想要的。

## 更新记录
2019-08-05
* 修改doh端口为1053

2019-07-14
* 增加自建doh服务

2019-07-01
* 增加cn模式

2019-06-22
* 采用dns-over-https代替dnscrypt
* 更新广告列表

2019-05-10
* 增加另外一个广告源
* 修改ad.hosts为泛域名解析方式

2019-04-25
* 初版
