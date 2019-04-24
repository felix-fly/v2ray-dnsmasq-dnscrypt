function FindProxyForURL(url, host) {
  var domain = host.replace(/^www\./, '');
  if (gwMap[domain]) return 'SOCKS5 192.168.1.1:12345';
  return 'DIRECT';
}