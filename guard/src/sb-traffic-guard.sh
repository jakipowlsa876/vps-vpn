#!/bin/bash
# 流量守卫（每分钟由 sb-guard.timer 调用）：
# 1) 按计费周期统计外层网卡的出站字节（入站不计）
# 2) 出站达到上限时只停 sing-box 节点服务（不关机、保留 SSH），跨周期自动恢复
# 3) 每轮刷新 /var/lib/sb-guard/info.env 并调用 sb-gen-sub.sh 重生成订阅
# 全部可调值来自 /etc/s-box/guard.conf（由 install.sh 生成）：
#   LIMIT_GB   每周期流量上限（GiB，默认 200；填 0 = 不限量，只统计不停机）
#   BUFFER_PCT 到量停机的缓冲百分比（默认 99：用到上限的 99% 就停，防口径差超额）
#   COUNT_MODE 统计口径：out = 只数出站（默认）；both = 出站+入站
#   RESET_DAY  每月重置日（默认 1）
#   IFACE      外层网卡名（安装时自动探测）
set -u
CONF=/etc/s-box/guard.conf
[ -f "$CONF" ] && . "$CONF"
IFACE=${IFACE:-eth0}
LIMIT_GB=${LIMIT_GB:-200}
BUFFER_PCT=${BUFFER_PCT:-99}
COUNT_MODE=${COUNT_MODE:-out}
RESET_DAY=${RESET_DAY:-1}
LIMIT_BYTES=$(awk -v g="$LIMIT_GB" 'BEGIN{printf "%d", g*1073741824}')
STOP_BYTES=$(awk -v b="$LIMIT_BYTES" -v p="$BUFFER_PCT" 'BEGIN{printf "%d", b*p/100}')
STATE_DIR=/var/lib/sb-guard
mkdir -p "$STATE_DIR"

# 计算本周期起点与下次重置日（RESET_DAY 超过当月天数时按月末算）
cycle_start_for() {
  local ym="$1" dim eff
  dim=$(date -d "$ym-01 +1 month -1 day" +%d)
  eff=$(( RESET_DAY < 10#$dim ? RESET_DAY : 10#$dim ))
  date -d "$ym-$eff" +%F
}
TODAY=$(date +%F)
DOM=$(date +%-d)
YM=$(date +%Y-%m)
if [ "$DOM" -ge "$RESET_DAY" ]; then
  CYCLE_START=$(cycle_start_for "$YM")
else
  PREV_YM=$(date -d "$YM-01 -1 month" +%Y-%m)
  CYCLE_START=$(cycle_start_for "$PREV_YM")
fi
NEXT_RESET=$(date -d "$CYCLE_START +1 month" +%F)
# 下次重置日也要落在 RESET_DAY 上（cycle_start_for 已保证起点，+1 month 后再校准）
NEXT_RESET=$(cycle_start_for "$(date -d "$CYCLE_START +1 month" +%Y-%m)")
DAYS_LEFT=$(( ( $(date -d "$NEXT_RESET" +%s) - $(date -d "$TODAY" +%s) ) / 86400 ))
CS_NUM=$(date -d "$CYCLE_START" +%Y%m%d)

BOTH=0; [ "$COUNT_MODE" = "both" ] && BOTH=1
USED=$(vnstat -i "$IFACE" --json d 2>/dev/null | jq -r --argjson cs "$CS_NUM" --argjson both "$BOTH" '
  [.interfaces[0].traffic.days[]?
   | select((.date.year*10000 + .date.month*100 + .date.day) >= $cs)
   | (.tx + (if $both == 1 then .rx else 0 end))] | add // 0' 2>/dev/null)
case "$USED" in ''|*[!0-9]*) USED=0;; esac
REMAIN=$((LIMIT_BYTES - USED)); [ "$REMAIN" -lt 0 ] && REMAIN=0
REMAIN_GB=$(awk -v b="$REMAIN" 'BEGIN{printf "%.2f", b/1073741824}')
USED_GB=$(awk -v b="$USED" 'BEGIN{printf "%.2f", b/1073741824}')
UNLIMITED=0; [ "$LIMIT_BYTES" -le 0 ] && UNLIMITED=1
cat > "$STATE_DIR/info.env" <<EOF
USED_BYTES=$USED
USED_GB=$USED_GB
REMAIN_GB=$REMAIN_GB
LIMIT_GB=$LIMIT_GB
UNLIMITED=$UNLIMITED
NEXT_RESET=$NEXT_RESET
DAYS_LEFT=$DAYS_LEFT
EOF
if [ "$UNLIMITED" = "0" ] && [ "$USED" -ge "$STOP_BYTES" ]; then
  if systemctl is-active --quiet sing-box; then
    systemctl stop sing-box
    echo "$(date '+%F %T') used=${USED} >= stop=${STOP_BYTES} (limit=${LIMIT_BYTES}, buffer=${BUFFER_PCT}%), sing-box stopped" >> "$STATE_DIR/guard.log"
  fi
  touch "$STATE_DIR/stopped_by_limit"
else
  if [ -f "$STATE_DIR/stopped_by_limit" ] && ! systemctl is-active --quiet sing-box; then
    systemctl start sing-box
    rm -f "$STATE_DIR/stopped_by_limit"
    echo "$(date '+%F %T') new cycle, sing-box restarted" >> "$STATE_DIR/guard.log"
  fi
fi
/usr/local/bin/sb-gen-sub.sh
