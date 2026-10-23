#!/usr/bin/env python3
# 订阅服务：按口令路径 /<SUBTOKEN>/clash.yaml 返回订阅文件，并在响应头里带上
# Subscription-Userinfo（已用/总量/到期），客户端订阅卡片据此显示进度条。
# 全部参数来自 /etc/s-box/guard.conf（由 install.sh 生成），本文件无硬编码数值：
#   SUBTOKEN 订阅口令路径；SUB_PORT 监听端口；LIMIT_GB 每周期上限（GiB）
# 已用量与到期日每次请求时实时读 /var/lib/sb-guard/info.env（守卫每分钟刷新）。
import os
from datetime import datetime, timezone, timedelta
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

BASE = "/var/lib/sb-guard/sub"
INFO = "/var/lib/sb-guard/info.env"
CONF = "/etc/s-box/guard.conf"
TZ = timezone(timedelta(hours=8))


def read_kv(path):
    d = {}
    try:
        with open(path) as f:
            for line in f:
                line = line.strip()
                if "=" in line and not line.startswith("#"):
                    k, v = line.split("=", 1)
                    d[k.strip()] = v.strip()
    except OSError:
        pass
    return d


CONF_DATA = read_kv(CONF)
try:
    LIMIT_GB = float(CONF_DATA.get("LIMIT_GB", "200"))
except ValueError:
    LIMIT_GB = 200
TOTAL = int(LIMIT_GB * 1073741824) if LIMIT_GB > 0 else 0
try:
    PORT = int(CONF_DATA.get("SUB_PORT", "18080"))
except ValueError:
    PORT = 18080


class H(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def _serve(self, head_only=False):
        token = read_kv(CONF).get("SUBTOKEN", "")
        if not token or self.path != f"/{token}/clash.yaml":
            self.send_response(404)
            self.end_headers()
            return
        info = read_kv(INFO)
        try:
            used = int(info.get("USED_BYTES", "0"))
        except ValueError:
            used = 0
        expire = 0
        try:
            dt = datetime.strptime(info.get("NEXT_RESET", ""), "%Y-%m-%d").replace(tzinfo=TZ)
            expire = int(dt.timestamp())
        except ValueError:
            pass
        fpath = os.path.join(BASE, token, "clash.yaml")
        try:
            with open(fpath, "rb") as f:
                body = f.read()
        except OSError:
            self.send_response(404)
            self.end_headers()
            return
        self.send_response(200)
        self.send_header("Content-Type", "text/yaml; charset=utf-8")
        if TOTAL > 0:
            self.send_header(
                "Subscription-Userinfo",
                f"upload=0; download={used}; total={TOTAL}; expire={expire}",
            )
        self.send_header("Profile-Update-Interval", "24")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        if not head_only:
            self.wfile.write(body)

    def do_GET(self):
        self._serve(False)

    def do_HEAD(self):
        self._serve(True)


if __name__ == "__main__":
    ThreadingHTTPServer(("0.0.0.0", PORT), H).serve_forever()
