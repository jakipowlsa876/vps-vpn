#!/bin/bash
# 流量守卫一键安装（可复用版）：给 sing-box-yg 装好的节点加一层
# 「按周期统计出站流量、到量自动停、下周期自动恢复、订阅带流量信息行与进度条」。
#
# 用法（任选其一）：
#   git clone 本仓库后：        sudo bash guard/install.sh
#   不克隆、直接拉脚本：        sudo bash <(curl -sL https://raw.githubusercontent.com/jakipowlsa876/vps-vpn/main/guard/install.sh)
#
# 可调项（环境变量传入，都有默认值，本脚本与配套脚本内无任何机器相关硬编码）：
#   LIMIT_GB    每周期流量上限，单位 GiB         默认 200；填 0 = 不限量（只统计不停机）
#   BUFFER_PCT  到量停机缓冲百分比               默认 99（用到上限的 99% 就停）
#   COUNT_MODE  统计口径 out=只出站 both=双向   默认 out
#   RESET_DAY   每月重置日                       默认 1
#   SUB_PORT    订阅服务端口                     默认 18080
#   NAME_PREFIX 订阅里节点名前缀                 默认 自建
#   IFACE       外层网卡名                       默认自动探测
#   SERVER_IP   对外地址                         默认从节点直链自动提取
#   ROTATE_TOKEN=1  重新生成订阅口令             默认保留已有口令
#   REPO_RAW    远程拉取配套文件的仓库地址       默认本仓库 main 分支
#
# 前置条件：已用 sb.sh（sing-box-yg）装好节点，/etc/s-box/jhsub.txt 存在；
#           系统为 Debian/Ubuntu（依赖 vnstat、jq、python3，缺了会自动装）。
set -euo pipefail

LIMIT_GB=${LIMIT_GB:-200}
BUFFER_PCT=${BUFFER_PCT:-99}
COUNT_MODE=${COUNT_MODE:-out}
RESET_DAY=${RESET_DAY:-1}
SUB_PORT=${SUB_PORT:-18080}
NAME_PREFIX=${NAME_PREFIX:-自建}
ROTATE_TOKEN=${ROTATE_TOKEN:-0}
REPO_RAW=${REPO_RAW:-https://raw.githubusercontent.com/jakipowlsa876/vps-vpn/main/guard}
CONF=/etc/s-box/guard.conf
SRC_DIR=""

die() { echo "错误：$*" >&2; exit 1; }
[ "$(id -u)" = "0" ] || die "请用 root 运行（sudo bash install.sh）"
[ -f /etc/s-box/jhsub.txt ] || die "没找到 /etc/s-box/jhsub.txt，请先用 sb.sh 装好节点再运行本脚本"
command -v python3 >/dev/null || die "缺少 python3"

# 定位配套源文件：优先用脚本同目录的 src/，否则从仓库远程拉取
SCRIPT_DIR=$(cd "$(dirname "$0")" 2>/dev/null && pwd || echo "")
if [ -n "$SCRIPT_DIR" ] && [ -f "$SCRIPT_DIR/src/sb-traffic-guard.sh" ]; then
  SRC_DIR="$SCRIPT_DIR"
else
  TMPD=$(mktemp -d)
  mkdir -p "$TMPD/src" "$TMPD/systemd"
  for f in sb-traffic-guard.sh sb-gen-sub.sh sb-sub-server.py parse_jhsub.py; do
    curl -fsSL "$REPO_RAW/src/$f" -o "$TMPD/src/$f" || die "下载 $f 失败"
  done
  for f in sb-guard.service sb-guard.timer sb-sub.service; do
    curl -fsSL "$REPO_RAW/systemd/$f" -o "$TMPD/systemd/$f" || die "下载 $f 失败"
  done
  SRC_DIR="$TMPD"
fi

# 依赖：vnstat（流量统计）、jq（解析统计结果）
NEED=""
command -v vnstat >/dev/null || NEED="$NEED vnstat"
command -v jq >/dev/null || NEED="$NEED jq"
if [ -n "$NEED" ]; then
  export DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a
  apt-get update -qq && apt-get install -y -qq $NEED
fi

# 从节点直链自动提取参数（地址、UUID、端口、Reality 公钥等）
eval "$(python3 "$SRC_DIR/src/parse_jhsub.py" /etc/s-box/jhsub.txt)"
[ -n "${UUID:-}" ] && [ -n "${VL_PORT:-}" ] || die "直链解析不完整，拿不到 UUID 或 VLESS 端口"
SERVER_IP=${SERVER_IP:-${SERVER_IP:-}}
[ -n "$SERVER_IP" ] || die "没能确定对外地址，请用 SERVER_IP=你的地址 重新运行"

# 网卡自动探测（默认路由所在网卡）
if [ -z "${IFACE:-}" ]; then
  IFACE=$(ip -o route get 1.1.1.1 2>/dev/null | sed -n 's/.* dev \([^ ]*\).*/\1/p' | head -1)
  [ -n "$IFACE" ] || IFACE=$(ip -o route show default 2>/dev/null | sed -n 's/.* dev \([^ ]*\).*/\1/p' | head -1)
  [ -n "$IFACE" ] || IFACE=eth0
fi

# 订阅口令：已有则保留（除非 ROTATE_TOKEN=1），否则随机生成
OLD_TOKEN=""
if [ -f "$CONF" ]; then
  OLD_TOKEN=$(grep -E '^SUBTOKEN=' "$CONF" | head -1 | cut -d= -f2- || true)
fi
if [ -n "$OLD_TOKEN" ] && [ "$ROTATE_TOKEN" != "1" ]; then
  SUBTOKEN="$OLD_TOKEN"
else
  SUBTOKEN=$(head -c 8 /dev/urandom | od -An -tx1 | tr -d ' \n')
fi

# 写统一配置（权限 600：里面含节点参数与订阅口令，不进任何仓库）
mkdir -p /etc/s-box /var/lib/sb-guard
cat > "$CONF" <<EOF
# 由 guard/install.sh 生成：节点参数（自动提取）+ 可调项。改完执行
# systemctl restart sb-sub.service 并等守卫下一分钟刷新即可生效。
SERVER_IP=$SERVER_IP
UUID=$UUID
VL_PORT=$VL_PORT
PBK=${PBK:-}
SID=${SID:-}
REALITY_SNI=${REALITY_SNI:-apple.com}
VM_PORT=${VM_PORT:-}
HY2_PORT=${HY2_PORT:-}
HY2_PIN=${HY2_PIN:-}
WEB_SNI=${WEB_SNI:-www.bing.com}
TU_PORT=${TU_PORT:-}
AN_PORT=${AN_PORT:-}
SUBTOKEN=$SUBTOKEN
SUB_PORT=$SUB_PORT
LIMIT_GB=$LIMIT_GB
BUFFER_PCT=$BUFFER_PCT
COUNT_MODE=$COUNT_MODE
RESET_DAY=$RESET_DAY
IFACE=$IFACE
NAME_PREFIX=$NAME_PREFIX
EOF
chmod 600 "$CONF"

# 安装脚本与系统服务
install -m 755 "$SRC_DIR/src/sb-traffic-guard.sh" /usr/local/bin/sb-traffic-guard.sh
install -m 755 "$SRC_DIR/src/sb-gen-sub.sh" /usr/local/bin/sb-gen-sub.sh
install -m 755 "$SRC_DIR/src/sb-sub-server.py" /usr/local/bin/sb-sub-server.py
if [ -f "$SRC_DIR/systemd/sb-guard.service" ]; then UNIT_SRC="$SRC_DIR/systemd"; else UNIT_SRC="$SRC_DIR/systemd"; fi
install -m 644 "$UNIT_SRC/sb-guard.service" /etc/systemd/system/sb-guard.service
install -m 644 "$UNIT_SRC/sb-guard.timer" /etc/systemd/system/sb-guard.timer
install -m 644 "$UNIT_SRC/sb-sub.service" /etc/systemd/system/sb-sub.service

# 流量统计服务就位
systemctl enable --now vnstat >/dev/null 2>&1 || true
vnstat -i "$IFACE" >/dev/null 2>&1 || vnstat --add -i "$IFACE" >/dev/null 2>&1 || true
systemctl restart vnstat >/dev/null 2>&1 || true

systemctl daemon-reload
systemctl enable --now sb-guard.timer >/dev/null 2>&1 || systemctl enable sb-guard.timer
systemctl enable sb-sub.service >/dev/null 2>&1 || true
systemctl restart sb-sub.service
/usr/local/bin/sb-traffic-guard.sh || true

echo "=================================================="
echo "流量守卫安装完成"
echo "  网卡：$IFACE    上限：${LIMIT_GB} GiB/周期（0=不限量）    口径：$COUNT_MODE    缓冲：${BUFFER_PCT}%    重置日：每月 ${RESET_DAY} 号"
echo "  订阅地址：http://${SERVER_IP}:${SUB_PORT}/${SUBTOKEN}/clash.yaml"
echo "  提醒：云厂商防火墙需放行订阅端口 ${SUB_PORT}（TCP）和五个节点端口"
echo "=================================================="
