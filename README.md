# v2ray-dnsmasq-dnscrypt

本文为在路由器openwrt中使用v2ray的另一种解决方案，之前相对简单的方案在这里[v2ray-openwrt](https://github.com/felix-fly/v2ray-openwrt)。重点说下本方案的不同或者特点：

* dnsmasq负责园内的解析（默认）
* dnsmasq直接屏蔽广告域名
* dnscrypt负责园外的解析（基于gw表）
* ipset记录园外域名的ip
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

作战方针制定好了那就开始战略部署吧。早些年时候ss的解决方案正好可以参考，dnsmasq系列相关的教程多如牛毛。经过一番比较和尝试，决定采用dnsmasq+dnscrypt+ipset+iptables这一组合，openwrt本身已经有dnsmasq、iptables、ipset，dnscrypt准确的来说是一种规范，落实到软件上话有多种具体的实现，dnscrypt-proxy就是其中的一种，openwrt提供的就是这种，如果你用的是lede编译的固件，软件源需要添加自定义的源，就把官方的18.06.2的源地址填进去好了，除了某些特殊依赖内核版本的软件不能安装，大部分都可以正常安装使用。更新完列表然后搜索dnscrypt，安装luci-app-dnscrypt-proxy这个就好了，其它依赖的都会自动安装好。

### 下载hosts文件

* [ad.hosts](./ad.hosts)
* [gw.hosts](./gw.hosts)
* [gw-mini.hosts](./gw-mini.hosts)

gw-mini是gw的子集，仅包含了常用的一些网站域名，可根据个人需求选择。

通过ssh上传的路由器，路径此处为
```
/etc/config/v2ray/
```
你可以放到自己喜欢的路径下，注意与下面的dnsmasq.conf配置中保持一致即可。看到有人说可以开机自动复制到/tmp目录，然后dnsmasq从/tmp下读文件更快，/tmp路径实际是内存。

### dnsmasq配置

可以在luci界面进行配置，也可以直接在dnsmasq.conf文件里配置，luci界面的优先级更高，换句话说就是会覆盖dnsmasq.conf文件里相同的配置项。

```
vi /etc/dnsmasq.conf
```
加入下面的配置项
```
conf-dir=/etc/config/v2ray/, *.hosts
```

### dnscrypt-proxy配置

通过luci界面完成，选择一个可用的server，选择后保存并应用，然后切换到log那个tab看看是不是成功了。配置那个tab最下面的修改dnsmasq的复选框不要勾，这里应该有bug，取消保存了之后又勾上了，勾了也没关系，只要确认dnsmasq配置里转发dns没有设置为127.0.0.1:5353，还有第二个tab里忽略resolve没有选中，并且resolve文件地址为默认的文件。此处的调整是因为我们不是把所有的dns请求都转发给dnscrypt-proxy，而是默认用园内的dns服务器来解析，园内的dns服务器可以是自动获取的ISP提供的地址，也可以是你自己定义的114这种类似的公共dns地址。

### iptables规则

在 **luci-网络-防火墙-自定义规则** 下添加

```
ipset -N gw iphash
iptables -t nat -A PREROUTING -p tcp -m set --match-set gw dst -j REDIRECT --to-port 12345
iptables -t nat -A OUTPUT -p tcp -m set --match-set gw dst -j REDIRECT --to-port 12345
```

### v2ray配置

替换==包含的内容为你自己的配置

```
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

2019-05-10
* 增加另外一个广告源
* 修改ad.hosts为泛域名解析方式

2019-04-25
* 初版
