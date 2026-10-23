# 个人节点一键部署

在自己的服务器上一条命令装完全套：**五协议直连节点 + 流量守卫 + 带流量信息行和进度条的订阅**，装完直接打印订阅地址。全套参数可调，换任何一台符合条件的服务器都能直接用。

## 一条命令部署

```bash
sudo bash <(curl -sL https://raw.githubusercontent.com/jakipowlsa876/vps-vpn/main/deploy.sh)
```

部署过程全自动：装节点（简单模式：随机端口、自签证书）→ 装守卫 → 打印订阅地址和需要放行的端口清单。装完不自动重启服务器。

也可以分开装：先 `bash clzzx.sh` 按菜单装节点，再 `bash guard/install.sh` 装守卫，效果一样。

## 适合部署在什么服务器上

**适合：**
- 有独立公网 IP 的服务器（IPv4、IPv6、双栈均可），英特尔与 ARM 架构都支持
- 系统为 Debian / Ubuntu（守卫层按这类系统的服务管理方式编写）
- 配置很低也行：节点程序本身占用几十兆内存，1 核 1G 足够

**不适合：**
- NAT 共用 IP 的机器（多人共用一个地址、只分几个端口）——本项目要随机开五个节点端口，必须独占 IP
- Alpine 等小众系统：节点脚本本身能装，但守卫层未适配，需要单独处理

**注意：**
- 普通服务器没有云厂商那层防火墙时，端口装好即通；在谷歌云这类平台上，要按部署结尾打印的清单去控制台放行端口
- 只装直连协议，不用隧道、不用 CDN 加速——走 CDN 的流量在部分平台（如谷歌云）不计入免费额度、会产生费用

## 装完得到什么

- 五个直连节点：VLESS-Reality、VMess、Hysteria2、TUIC、AnyTLS（参数在服务器 `/etc/s-box/` 下）
- 一个 Clash/Mihomo 订阅地址，订阅里带三行信息：剩余流量、距离下次重置天数、下次重置日期（信息行本身也是能用的节点）
- 客户端订阅卡片能显示「已用 / 总量」进度条和到期日（即下次重置日）
- 服务器上输入 `clzzx` 打开管理菜单（换端口、看直链、更新、卸载都在里面）

## 流量守卫是怎么工作的

节点脚本本身不管流量，守卫层补上三件事：

- **统计**：用系统工具（vnstat）记整张外网网卡的流量账本，按天保存、重启不丢；守卫每分钟把本周期已用加总一次
- **拦截**：本周期用量达到停机线时，只停节点服务——机器、登录、守卫、订阅都继续跑；跨过重置日零点后一分钟内自动恢复，全程不用人管
- **展示**：剩余流量、已用、进度条、到期日都用同一组数字，不会出现对不上的情况

### 流量账口径（重要，装之前先对齐）

| 项目 | 口径 |
|---|---|
| 数什么 | 整台机器的网卡流量，不只数节点程序（系统更新、传文件都算），与服务商账单口径一致，防漏算超额 |
| 默认方向 | 只数出站（入站免费是谷歌等多数平台的规矩）；商家双向计费的改 `COUNT_MODE=both` |
| 周期 | 按重置日切分（默认每月 1 号；按购买日计费的服务器把 `RESET_DAY` 填购买日） |
| 上限与缓冲 | `LIMIT_GB` 是周期上限；实际停机线 = 上限 × `BUFFER_PCT`（默认 99%），留一点防统计口径差（网卡计数与服务商计费有几个百分点以内的细微差别） |
| 不限量 | `LIMIT_GB=0` 表示不限量：只统计展示、永不停机；订阅第一行改为显示「本周期已用」，卡片不显示进度条（没有总量不硬凑） |
| 数据连续性 | 账本每 5 分钟落盘，突然断电最多丢最后几分钟；全新部署开机即装、无缺口；半路加装的机器，装之前的本周期流量统计不到，会晚一点触发上限 |

## 可调参数（部署时用环境变量传入，都有默认值）

```bash
LIMIT_GB=200 BUFFER_PCT=99 COUNT_MODE=out RESET_DAY=1 sudo -E bash <(curl -sL https://raw.githubusercontent.com/jakipowlsa876/vps-vpn/main/deploy.sh)
```

| 参数 | 默认 | 说明 |
|---|---|---|
| LIMIT_GB | 200 | 每周期流量上限（GiB）；谷歌标准层级免费额度即每月 200 GiB；填 0 = 不限量 |
| BUFFER_PCT | 99 | 停机缓冲百分比，用到上限的 99% 就停 |
| COUNT_MODE | out | out = 只数出站；both = 出站+入站（双向计费的商家用） |
| RESET_DAY | 1 | 每月重置日，与账单周期对齐 |
| SUB_PORT | 18080 | 订阅服务端口 |
| NAME_PREFIX | 自建 | 订阅里节点名的前缀 |

服务器地址、网卡、节点端口、订阅口令全部自动处理（地址从节点直链提取，口令随机生成），不需要填。

装完之后改参数：改服务器上的 `/etc/s-box/guard.conf`，再执行 `systemctl restart sb-sub.service`，守卫每分钟自动刷新订阅。

## 日常维护

- 管理菜单：服务器上输入 `clzzx`（改配置、换端口、看日志、更新脚本、卸载都在菜单里）
- 更新脚本：菜单第 7 项，更新源就是本仓库
- 守卫状态：`systemctl status sb-guard.timer sb-sub.service`

## Serv00 线

仓库里另有一套 Serv00/Hostuno 用的三协议脚本（`serv00.sh` 及配套保活文件、工作流），与上面的 VPS 线互不相干，按需自取：

```bash
bash <(curl -Ls https://raw.githubusercontent.com/jakipowlsa876/vps-vpn/main/serv00.sh)
```

## 卸载

- 节点：`clzzx` 菜单第 2 项
- 守卫：

```bash
sudo systemctl disable --now sb-guard.timer sb-sub.service
sudo rm /etc/systemd/system/sb-guard.service /etc/systemd/system/sb-guard.timer /etc/systemd/system/sb-sub.service
sudo rm /usr/local/bin/sb-traffic-guard.sh /usr/local/bin/sb-gen-sub.sh /usr/local/bin/sb-sub-server.py
sudo systemctl daemon-reload
```

## 常见问题

- **订阅卡片没有进度条**：刷新一次订阅即可；不限量模式（LIMIT_GB=0）本来就不发进度条
- **进度条没到 100% 节点就停了**：缓冲在起作用（默认 99% 停），不是故障；想精确停把 BUFFER_PCT 改 100
- **节点突然停了**：多半是到量了，看订阅第一行剩余是否为 0；跨重置日会自动恢复，也可以改大 LIMIT_GB 后等一分钟
- **换了台新机器**：直接跑一条命令部署，旧机器的数据（流量账本）不迁移、从零计

## 文件清单

| 文件 | 作用 |
|---|---|
| deploy.sh | 总入口：一条命令装全套 |
| clzzx.sh | 节点主脚本（菜单管理，快捷方式 clzzx） |
| guard/ | 流量守卫（安装脚本、三个组件、参数说明） |
| serv00.sh / serv00keep.sh / kp.sh | Serv00 线脚本与保活 |
| SSH.yml / serv00.yml | Serv00 线的 GitHub Actions 保活工作流（需在仓库设置里启用 Actions） |
| sbwpph_amd64 / sbwpph_arm64 | 节点核心程序（两种架构） |
| version / sversion | 两条线的版本标记（自更新比对用） |
| app.js / index.html | Serv00 保活网页文件 |

## 许可证

见仓库 LICENSE 文件。
