#!/bin/bash
# 由 sb-traffic-guard.sh 调用：读取 /var/lib/sb-guard/info.env，把带三行流量信息的
# Clash/Mihomo 订阅写到 /var/lib/sb-guard/sub/<token>/clash.yaml
# 三行信息节点与主 VLESS 节点共用同一套连接参数，选中也能正常上网、能测延迟。
# 节点参数与可调项全部来自 /etc/s-box/guard.conf（由 install.sh 生成），本脚本无硬编码数值。
set -u
CONF=/etc/s-box/guard.conf
INFO=/var/lib/sb-guard/info.env
[ -f "$CONF" ] && . "$CONF"
[ -f "$INFO" ] && . "$INFO"
REMAIN_GB=${REMAIN_GB:-0.00}
DAYS_LEFT=${DAYS_LEFT:-0}
NEXT_RESET=${NEXT_RESET:-未知}
if [ "${UNLIMITED:-0}" = "1" ]; then
  INFO1="本周期已用：${USED_GB:-0.00} GB"
else
  INFO1="剩余流量：${REMAIN_GB} GB"
fi
NAME_PREFIX=${NAME_PREFIX:-自建}
REALITY_SNI=${REALITY_SNI:-apple.com}
WEB_SNI=${WEB_SNI:-www.bing.com}
OUTDIR="/var/lib/sb-guard/sub/${SUBTOKEN}"
mkdir -p "$OUTDIR"

vless_block() {
  local name="$1"
  cat <<EOF
  - name: "${name}"
    type: vless
    server: ${SERVER_IP}
    port: ${VL_PORT}
    uuid: ${UUID}
    network: tcp
    udp: true
    tls: true
    flow: xtls-rprx-vision
    servername: ${REALITY_SNI}
    reality-opts:
      public-key: ${PBK}
      short-id: ${SID}
    client-fingerprint: chrome
EOF
}

{
echo "mixed-port: 7890"
echo "allow-lan: true"
echo "mode: rule"
echo "log-level: info"
echo "proxies:"
vless_block "$INFO1"
vless_block "距离下次重置剩余：${DAYS_LEFT} 天"
vless_block "下次重置日期：${NEXT_RESET}"
vless_block "${NAME_PREFIX}-VLESS直连"
cat <<EOF
  - name: "${NAME_PREFIX}-Hysteria2直连"
    type: hysteria2
    server: ${SERVER_IP}
    port: ${HY2_PORT}
    password: ${UUID}
    sni: ${WEB_SNI}
    fingerprint: ${HY2_PIN}
    alpn:
      - h3
    udp: true
  - name: "${NAME_PREFIX}-VMess直连"
    type: vmess
    server: ${SERVER_IP}
    port: ${VM_PORT}
    uuid: ${UUID}
    alterId: 0
    cipher: auto
    udp: true
    network: ws
    servername: ${WEB_SNI}
    ws-opts:
      path: ${UUID}-vm
      headers:
        Host: ${WEB_SNI}
  - name: "${NAME_PREFIX}-TUIC直连"
    type: tuic
    server: ${SERVER_IP}
    port: ${TU_PORT}
    uuid: ${UUID}
    password: ${UUID}
    sni: ${WEB_SNI}
    skip-cert-verify: true
    alpn:
      - h3
    congestion-controller: bbr
    udp-relay-mode: native
    udp: true
  - name: "${NAME_PREFIX}-AnyTLS直连"
    type: anytls
    server: ${SERVER_IP}
    port: ${AN_PORT}
    password: ${UUID}
    sni: ${WEB_SNI}
    skip-cert-verify: true
    udp: true
proxy-groups:
  - name: "${NAME_PREFIX}节点"
    type: select
    proxies:
      - "$INFO1"
      - "距离下次重置剩余：${DAYS_LEFT} 天"
      - "下次重置日期：${NEXT_RESET}"
      - "${NAME_PREFIX}-VLESS直连"
      - "${NAME_PREFIX}-Hysteria2直连"
      - "${NAME_PREFIX}-VMess直连"
      - "${NAME_PREFIX}-TUIC直连"
      - "${NAME_PREFIX}-AnyTLS直连"
      - DIRECT
rules:
  - MATCH,${NAME_PREFIX}节点
EOF
} > "$OUTDIR/clash.yaml.tmp"
mv "$OUTDIR/clash.yaml.tmp" "$OUTDIR/clash.yaml"
