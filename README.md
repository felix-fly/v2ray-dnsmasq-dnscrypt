# v2ray-dnsmasq-doh

本文为在路由器openwrt中使用v2ray的另一种解决方案，之前相对简单的方案在这里[v2ray-openwrt](https://github.com/felix-fly/v2ray-openwrt)。重点说下本方案的不同或者特点：

* dnsmasq负责园内的解析（默认）
* dnsmasq直接屏蔽广告域名
* 分流两种方式，根据需求选择
  * gw模式：dnsmasq将园外域名解析后的ip地址加入ipset（推荐）
  * cn模式：从apnic获取的园内ip段加入ipset
* 园外域名解析有三种方式，任选其中一种即可
  * v2ray开另外一个端口（推荐）
  * 通过tproxy将udp流量转发给v2ray
  * 转发给dns-over-https(doh)
* iptables屏蔽广告ip
* iptables根据ipset转发指定流量
* v2ray只负责进站出站

gw列表将子域名提升到了主域名，同时增加了一些常见的园外网站，加快访问速度。

## 下载v2ray

可以从我的另一个repo的[release](https://github.com/felix-fly/v2ray-openwrt/releases)下找自己对应平台的文件，压缩包内只包含v2ray单文件，如果不喜欢可以自行从官方渠道下载。

## 下载hosts和ips文件

gw模式不需要cn.ips文件。gw.hosts与gw-udp.hosts互斥，选择其一。

* [v2ray.service](./v2ray.service) # v2ray服务
* [ad.hosts](./ad.hosts) # 屏蔽广告
* [ad.ips](./ad.ips) # 广告ip
* [gw.hosts](./gw.hosts) # 某个域名列表，用于gw模式
* [gw.ips](./gw.ips) # 某个ip列表，用于gw模式
* [gw-udp.hosts](./gw.hosts) # 某个域名列表，用于gw模式，通过UDP转发，默认使用8.8.8.8，可自行替换为其它
* [cn.ips](./cn.ips) # 从apnic提取出来的ip段集合，用于cn模式（园内直连）

通过ssh上传到路由器，路径此处为
```shell
/etc/config/v2ray/
```
你可以放到自己喜欢的路径下，注意与下面的dnsmasq.conf配置中保持一致即可。

添加执行权限

```shell
chmod +x /etc/config/v2ray/v2ray
```

## 添加v2ray服务

服务自启动

```shell
chmod +x /etc/config/v2ray/v2ray.service
ln -s /etc/config/v2ray/v2ray.service /etc/init.d/v2ray
/etc/init.d/v2ray enable
```

开启

```shell
/etc/init.d/v2ray start
```

关闭

```shell
/etc/init.d/v2ray stop
```

## dnsmasq配置

可以在luci界面进行配置，也可以直接在dnsmasq.conf文件里配置，luci界面的优先级更高，换句话说就是会覆盖dnsmasq.conf文件里相同的配置项。

```shell
vi /etc/dnsmasq.conf
```
加入下面的配置项
```shell
conf-dir=/etc/config/v2ray, *.hosts
```
dnsmasq配置不正确可能会导致无法上网，这里修改完了可以用下面的命令测试一下
```shell
dnsmasq -test
```

## 园外域名解析及iptables规则

iptables配置要谨慎，错误的配置会造成无法连接路由器，只能重置路由器（恢复出厂设置）。为了安全，可以先通过ssh登陆到路由器，直接执行需要添加的iptables规则进行测试，如果发现终端不再响应，可能就是规则有问题，这时重启路由即可，刚刚执行的规则不会被保存。测试正常再添加到系统配置 **luci-网络-防火墙-自定义规则** 

此处提供的v2ray配置文件供参考使用，注意替换==包含的内容为你自己的，目前采用ws作为底层传输协议，服务端及nginx相关配置可度娘。

服务端配置文件 [server-config.json](./server-config.json)

### (1) v2ray开另外一个端口（推荐）

配置简单，一般情况下路由器已包含必要的模块（ipset、dnsmasq-full），不需要额外安装。

cn模式需要将YOUR_SERVER_IP替换为实际的ip地址，局域网不是192.168.1.x段的根据实际情况修改。

客户端配置文件 [client-dns.json](./client-dns.json)

gw模式防火墙规则

```shell
ipset -R < /etc/config/v2ray/ad.ips
ipset -R < /etc/config/v2ray/gw.ips
iptables -t filter -A INPUT -m set --match-set ad dst -j REJECT
iptables -t nat -A PREROUTING -p tcp -m set --match-set gw dst -j REDIRECT --to-port 12345
```

cn模式防火墙规则

```shell
ipset -R < /etc/config/v2ray/ad.ips
ipset -R < /etc/config/v2ray/cn.ips
iptables -t filter -A INPUT -m set --match-set ad dst -j REJECT
iptables -t mangle -N V2RAY
iptables -t mangle -A V2RAY -d 0.0.0.0 -j RETURN
iptables -t mangle -A V2RAY -d 127.0.0.1 -j RETURN
iptables -t mangle -A V2RAY -d 192.168.1.0/24 -j RETURN
iptables -t mangle -A V2RAY -d YOUR_SERVER_IP -j RETURN
iptables -t mangle -A V2RAY -m set --match-set cn dst -j RETURN
iptables -t mangle -A V2RAY -p tcp -j REDIRECT --to-port 12345 
iptables -t mangle -A PREROUTING -j V2RAY
```

### (2) 通过tproxy将udp流量转发给v2ray

使用tproxy路由器需要安装iptables-mod-tproxy模块

客户端配置文件 [client-tproxy.json](./client-tproxy.json)

gw模式防火墙规则

```shell
ipset -R < /etc/config/v2ray/ad.ips
ipset -R < /etc/config/v2ray/gw.ips
ip rule add fwmark 1 table 100
ip route add local 0.0.0.0/0 dev lo table 100
iptables -t filter -A INPUT -m set --match-set ad dst -j REJECT
iptables -t mangle -A PREROUTING -p tcp -m set --match-set gw dst -j TPROXY --on-port 12345 --tproxy-mark 1
iptables -t mangle -A PREROUTING -p udp -d 8.8.8.8 -j TPROXY --on-port 12345 --tproxy-mark 1
iptables -t mangle -A OUTPUT -m mark --mark 255 -j RETURN
iptables -t mangle -A OUTPUT -p udp -d 8.8.8.8 -j MARK --set-mark 1
```

cn模式防火墙规则

```shell
ipset -R < /etc/config/v2ray/ad.ips
ipset -R < /etc/config/v2ray/cn.ips
ip rule add fwmark 1 table 100
ip route add local 0.0.0.0/0 dev lo table 100
iptables -t filter -A INPUT -m set --match-set ad dst -j REJECT
iptables -t mangle -N V2RAY
iptables -t mangle -A V2RAY -d 0.0.0.0 -j RETURN
iptables -t mangle -A V2RAY -d 127.0.0.1 -j RETURN
iptables -t mangle -A V2RAY -d 192.168.1.0/24 -j RETURN
iptables -t mangle -A V2RAY -d YOUR_SERVER_IP -j RETURN
iptables -t mangle -A V2RAY -m set --match-set cn dst -j RETURN
iptables -t mangle -A V2RAY -p tcp -j TPROXY --on-port 12345 --tproxy-mark 1
iptables -t mangle -A V2RAY -p udp -j TPROXY --on-port 12345 --tproxy-mark 1
iptables -t mangle -A PREROUTING -j V2RAY
iptables -t mangle -A OUTPUT -m mark --mark 255 -j RETURN
```

### (3) 转发给dns-over-https(doh)

客户端配置文件 [client-doh.json](./client-doh.json)

gw模式防火墙规则

```shell
ipset -R < /etc/config/v2ray/ad.ips
ipset -R < /etc/config/v2ray/gw.ips
iptables -t filter -A INPUT -m set --match-set ad dst -j REJECT
iptables -t nat -A PREROUTING -p tcp -m set --match-set gw dst -j REDIRECT --to-port 12345
```

cn模式防火墙规则

```shell
ipset -R < /etc/config/v2ray/ad.ips
ipset -R < /etc/config/v2ray/cn.ips
iptables -t filter -A INPUT -m set --match-set ad dst -j REJECT
iptables -t mangle -N V2RAY
iptables -t mangle -A V2RAY -d 0.0.0.0 -j RETURN
iptables -t mangle -A V2RAY -d 127.0.0.1 -j RETURN
iptables -t mangle -A V2RAY -d 192.168.1.0/24 -j RETURN
iptables -t mangle -A V2RAY -d YOUR_SERVER_IP -j RETURN
iptables -t mangle -A V2RAY -m set --match-set cn dst -j RETURN
iptables -t mangle -A V2RAY -p tcp -j REDIRECT --to-port 12345 
iptables -t mangle -A PREROUTING -j V2RAY
```

路由器需要安装https_dns_proxy模块，安装后修改配置

```shell
vi /etc/config/https_dns_proxy
```
可以看到内置了google和couldflare两家的服务，但是由于众所周知的原因，可能不太好用，或者说不能用，修改成下面的，红鱼的地址填好，端口可以根据个人口味调整
```shell
config https_dns_proxy
  option listen_addr '127.0.0.1'
  option listen_port '1053'
  option user 'nobody'
  option group 'nogroup'
  option subnet_addr ''
  option proxy_server ''
  option url_prefix 'https://dns.rubyfish.cn/dns-query?'
```

上游服务端也可以在服务器上安装自己的doh服务，以下基于Ubuntu 18.04

```shell
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

```shell
sudo vi /etc/dns-over-https/doh-server.conf
```

修改服务器上nginx的配置，添加

```shell
location /dns-query {
  proxy_redirect off;
  proxy_set_header Host $http_host;
  proxy_pass http://127.0.0.1:8053/dns-query;
}
```

nginx需要对外提供https访问，相关教程很多，这里不再赘述。

## 规则来源及更新

主要规则取自

* https://github.com/h2y/Shadowrocket-ADBlock-Rules
* https://github.com/neoFelhz/neohosts
* https://github.com/Hackl0us/SS-Rule-Snippet

生成的hosts文件不定期更新，你也可以clone到本地自己更新规则，添加删除你想要的site，或着fork一份做你想要的。

## 后话

已经有了简单的v2ray全包方案，为什么还要这个看上去要复杂的多的方案？需求。是的。

如果简单方案你用下来没有感觉到有什么问题，可以不用捣鼓这个了，洗洗睡吧。

下面来聊聊我的需求：

* 起因

  一直以来家里的主路由都是由k2p承担，刷padavan也很稳定，v2ray也一直默默的守护着，一切都很和谐。但是下载速度一直都不是很理想，离100m的标称带宽差距很悬殊，虽说网速不稳定但是不能一直这么低吧。有次下载时刚好登陆了路由看到cpu负载一直很高，下载完了才回复到正常水平。之前论坛就有人说v2ray比较吃性能，差的路由就不要折腾了。看来mt7621这个于v2ray而言应该是很差了（其实个人感觉还可以啊，不至于那么差啦）。

  于是又把吃灰的k3翻出来，就路由来说这个应该不差了吧，咱不能拿pc的来比是不。话说这k3之前被刷的没了5g Wi-Fi，虽然2.4g可以勉强用，但是心里总归不痛快，于是又google了一大圈，各种折腾，重置、刷机、各个版本。。。现在可以来总结下了，进cef恢复nvram可以解决大部分问题，还要一个要注意的是固件版本，现在openwrt官方的snapshot已经支持k3了，用openwrt官方固件的话，5g需要国家us，信道149然后重启就有5g信号了，这不知道是什么鬼，现在用lede的自编译固件，官方的没有那些定制软件，等它慢慢完善吧。

  刷好了固件，v2ray等等各种配置好，然后悄悄的替换下已不堪重负的k2p，开足马力下载。果不出其然，速度是上来了，但是还是没能跑满带宽，峰值也就8～9m的样子，赶快登上路由看看，cpu还是很高，看来k3在v2ray面前也只能惭愧的低下了原本高昂的头颅。

* 分析探索

  又翻了翻v2ray的文档、各种文章、论坛，也没什么收获，看来只能自己想办法了。那么就来分析一下，目前的方案所有的流量都进v2ray，然后由v2ray根据路由规则选择不同的出站口，这样一来v2ray就是一个中心节点，承担了全部的工作（兄弟，你辛苦了），小流量情况下完全ok，但是大流量时cpu就会上去。基于此，于是想把路由的这块任务分离出去，v2ray只负责单一的进站和出站，只有需要的流量才会进到v2ray，一般情况下的下载都是园内为主，所以这样可以大大的减轻v2ray的工作量。

## 新的方案

作战方针制定好了那就开始战略部署吧。早些年时候ss的解决方案正好可以参考，dnsmasq系列相关的教程多如牛毛。初版采用了dnsmasq+dnscrypt+ipset+iptables这一组合，使用一段时间后发现效果不好。由于提供dnscrypt解析的多为园外的服务器，解析速度不理想，很明显感觉网页打开缓慢，于是寻找新的方案。目前选择了dns-over-https这种，又名doh，具体是什么自行科普下。开始想自己搭建服务器，偶然发现红鱼已经有成熟的服务可用，尝试之后速度明显提升，不在卡白。openwrt安装也很简单，同样搜https_dns_proxy，个人觉得不用安装luci-app相关的，只要安装https_dns_proxy本身就可以了，luci那边界面配置没有自定义源，只有两个内置选项，用不起来。

## 更新记录
2020-02-12
* 优化了文档内容及顺序
* gw列表优化

2019-12-19
* 增加gw及ad列表中ip部分的处理
* 去掉gw-mini用处不大

2019-12-18
* 文档内容细节优化

2019-12-06
* 增加UDP转发

2019-10-16
* 更新配置样例

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
