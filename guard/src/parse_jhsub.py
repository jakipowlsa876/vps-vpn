#!/usr/bin/env python3
"""解析 sing-box-yg 生成的 /etc/s-box/jhsub.txt（五条直链），
输出 KEY=VALUE 行供 install.sh 写入 guard.conf。
只做解析，不含任何机器相关数据。
"""
import base64
import json
import re
import sys
from urllib.parse import urlparse, parse_qs, unquote

out = {}


def q1(qs, key):
    v = parse_qs(qs).get(key, [""])[0]
    return unquote(v)


for raw in open(sys.argv[1], encoding="utf-8", errors="ignore"):
    line = raw.strip()
    if line.startswith("vless://"):
        u = urlparse(line)
        out["UUID"] = u.username or ""
        out["SERVER_IP"] = u.hostname or ""
        out["VL_PORT"] = str(u.port or "")
        out["PBK"] = q1(u.query, "pbk")
        out["SID"] = q1(u.query, "sid")
        out["REALITY_SNI"] = q1(u.query, "sni") or "apple.com"
    elif line.startswith("vmess://"):
        payload = line[len("vmess://"):].split("#")[0]
        payload += "=" * (-len(payload) % 4)
        try:
            d = json.loads(base64.b64decode(payload))
            out["VM_PORT"] = str(d.get("port", ""))
        except Exception:
            pass
    elif line.startswith("hysteria2://") or line.startswith("hy2://"):
        u = urlparse(line)
        out["HY2_PORT"] = str(u.port or "")
        out["HY2_PIN"] = q1(u.query, "pinSHA256")
        out["WEB_SNI"] = q1(u.query, "sni") or out.get("WEB_SNI", "www.bing.com")
    elif line.startswith("tuic://"):
        u = urlparse(line)
        out["TU_PORT"] = str(u.port or "")
    elif line.startswith("anytls://"):
        u = urlparse(line)
        out["AN_PORT"] = str(u.port or "")

for k in ["SERVER_IP", "UUID", "VL_PORT", "PBK", "SID", "REALITY_SNI",
          "VM_PORT", "HY2_PORT", "HY2_PIN", "WEB_SNI", "TU_PORT", "AN_PORT"]:
    if out.get(k):
        print(f"{k}={out[k]}")
