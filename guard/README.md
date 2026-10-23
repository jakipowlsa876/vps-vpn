# 流量守卫（guard）

给 clzzx.sh 装好的五协议直连节点补三件事：按周期统计整机流量、到量自动停/跨期自动恢复、订阅带流量信息行与进度条。

完整说明（部署、参数、流量账口径、卸载）见仓库根目录的 README.md，这里只列文件：

- `install.sh`：守卫一键安装（可单独运行；节点参数自动提取、订阅口令随机生成、已有口令保留）
- `src/sb-traffic-guard.sh`：每分钟统计与拦截
- `src/sb-gen-sub.sh`：生成带信息行的订阅
- `src/sb-sub-server.py`：订阅服务（附带进度条所需的流量信息）
- `src/parse_jhsub.py`：从节点直链提取参数
- `systemd/`：定时器与服务定义
- `config.example.env`：可调项说明

安装后实际配置在服务器 `/etc/s-box/guard.conf`（含节点参数与订阅口令，权限 600，不要提交进任何仓库）。
