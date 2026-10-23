#!/bin/bash
# 个人节点一键部署（总入口）：在全新服务器上一条命令装完全套——
# 五协议直连节点 + 流量守卫 + 带信息行和进度条的订阅，最后打印订阅地址。
#
# 用法：
#   sudo bash <(curl -sL https://raw.githubusercontent.com/jakipowlsa876/vps-vpn/main/deploy.sh)
# 或克隆仓库后：sudo bash deploy.sh
#
# 可调项（环境变量，透传给守卫安装，都有默认值）：
#   LIMIT_GB    每周期流量上限 GiB，默认 200；填 0 = 不限量
#   BUFFER_PCT  到量停机缓冲百分比，默认 99
#   COUNT_MODE  统计口径 out=只出站（默认） both=出入双向
#   RESET_DAY   每月重置日，默认 1
#   SUB_PORT    订阅端口，默认 18080
#   NAME_PREFIX 订阅里节点名前缀，默认 自建
#
# 前提：Debian/Ubuntu、root、独立 IP（NAT 共用 IP 的机器不适合）。
# 装完不会自动重启服务器；云厂商防火墙需按结尾清单放行端口。
set -euo pipefail

REPO_RAW=${REPO_RAW:-https://raw.githubusercontent.com/jakipowlsa876/vps-vpn/main}
export DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a
[ "$(id -u)" = "0" ] || { echo "错误：请用 root 运行（sudo）" >&2; exit 1; }

SCRIPT_DIR=$(cd "$(dirname "$0")" 2>/dev/null && pwd || echo "")
TMPD=$(mktemp -d)

# 1) 准备节点脚本 clzzx.sh（优先本地，其次从仓库拉取）
if [ -n "$SCRIPT_DIR" ] && [ -f "$SCRIPT_DIR/clzzx.sh" ]; then
  NODE_SH="$SCRIPT_DIR/clzzx.sh"
else
  NODE_SH="$TMPD/clzzx.sh"
  curl -fsSL "$REPO_RAW/clzzx.sh" -o "$NODE_SH" || { echo "错误：下载 clzzx.sh 失败" >&2; exit 1; }
fi

# 2) 无人值守安装节点：选单 1（一键安装）后一路回车走简单模式
#    （最新内核、自签证书、随机端口，均为脚本默认；装完当场验收产物）
if [ ! -f /etc/s-box/jhsub.txt ]; then
  echo ">>> 正在安装五协议节点（简单模式）……"
  printf '1\n\n\n\n\n\n\n\n' | bash "$NODE_SH" || true
fi
[ -f /etc/s-box/jhsub.txt ] || {
  echo "错误：节点安装未完成（没有生成 /etc/s-box/jhsub.txt）。" >&2
  echo "可手动运行 clzzx 按菜单安装，再单独运行 guard/install.sh 装守卫。" >&2
  exit 1
}
echo ">>> 节点安装完成"

# 3) 安装流量守卫（参数透传；本地有 guard/ 用本地，否则远程拉取其安装脚本）
if [ -n "$SCRIPT_DIR" ] && [ -f "$SCRIPT_DIR/guard/install.sh" ]; then
  GUARD_SH="$SCRIPT_DIR/guard/install.sh"
else
  GUARD_SH="$TMPD/guard-install.sh"
  curl -fsSL "$REPO_RAW/guard/install.sh" -o "$GUARD_SH" || { echo "错误：下载守卫安装脚本失败" >&2; exit 1; }
fi
LIMIT_GB=${LIMIT_GB:-200} BUFFER_PCT=${BUFFER_PCT:-99} COUNT_MODE=${COUNT_MODE:-out} \
RESET_DAY=${RESET_DAY:-1} SUB_PORT=${SUB_PORT:-18080} NAME_PREFIX=${NAME_PREFIX:-自建} \
  bash "$GUARD_SH"

# 4) 打印成果：订阅地址 + 待放行端口清单
. /etc/s-box/guard.conf
echo "=================================================="
echo "个人节点一键部署完成"
echo "  管理菜单：服务器上输入 clzzx"
echo "  订阅地址：http://${SERVER_IP}:${SUB_PORT}/${SUBTOKEN}/clash.yaml"
echo "  请在云厂商防火墙放行以下端口（节点端口为随机生成）："
echo "    TCP/UDP ${VL_PORT}（VLESS）  TCP ${VM_PORT}（VMess）  UDP ${HY2_PORT}（Hysteria2）"
echo "    UDP ${TU_PORT}（TUIC）  TCP ${AN_PORT}（AnyTLS）  TCP ${SUB_PORT}（订阅）"
echo "=================================================="
