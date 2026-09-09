# onekey-init_alp

一键 **Alpine Linux 系统初始化**（换源 + 更新 + 基础工具 + chrony + 网络调优）。

> 功能与 [onekey-init](https://github.com/guochan2019/onekey-init)（Debian 直装版）完全一致，平台层适配 **apk + OpenRC + musl**。

---

## 快速开始

> ⚠️ 需要 root 权限。适用 Alpine Linux（OpenRC）。建议在新建 Alpine LXC 后第一个运行。

```bash
# 方式一：一键直达（推荐）
sh <(wget -qO- https://raw.githubusercontent.com/guochan2019/onekey-init_alp/main/onekey-init_alp.sh)

# 方式二：gh CLI
gh repo clone guochan2019/onekey-init_alp && cd onekey-init_alp
chmod +x onekey-init_alp.sh && ./onekey-init_alp.sh
```

---

## 初始化流程（7 步）

| 步骤 | 说明 |
|------|------|
| 1/7 | 替换 apk 源为阿里镜像（`/etc/apk/repositories` 备份 `.bak`，按原版本号重建 main + community 两行） |
| 2/7 | 系统更新（`apk upgrade`） |
| 3/7 | 安装基础工具：curl、wget、nano、btop、iproute2、sudo、ca-certificates、unzip、tzdata、chrony（**不装 git/vim/net-tools，不装 nftables**） |
| 4/7 | chrony 时间同步（Alpine 无 systemd-timesyncd，直接启用 chronyd） |
| 5/7 | 网络调优：BBR + 连接跟踪 + TIME_WAIT + 缓冲区 + 端口范围（写入 `/etc/sysctl.conf` 逐条应用） |
| 6/7 | 系统参数（swappiness=10、vfs_cache_pressure=50）+ 时区 Asia/Shanghai |
| 7/7 | 启用 syslogd 限日志循环 + 清理 apk 缓存 |

---

## 与 Debian 直装版差异

| 项 | Debian 版 | Alpine 版 |
|----|-----------|-----------|
| 源 | deb822 阿里源（`debian.sources`） | apk 阿里镜像（`repositories`，版本号自适应） |
| 包管理 | apt | apk |
| cron | 安装 cron 包 | busybox crond（Alpine 内建） |
| 服务管理 | systemd | OpenRC（`rc-update` / `rc-service`） |
| IPv4 优先 | `/etc/gai.conf`（glibc） | **无需配置**：musl 按 AF_INET → AF_INET6 查询，天然 IPv4 优先 |
| 时区 | `timedatectl set-timezone` | 链接 zoneinfo（`/etc/localtime`，tzdata 包） |
| 日志限制 | journald 50M（drop-in） | 无 journald；busybox syslogd + 循环上限（`/etc/conf.d/syslogd`） |
| 邮件清理 | purge exim4 | Alpine 无 MTA 依赖问题，无对应项 |
| 内核模块加载 | `/etc/modules-load.d/` | `/etc/modules`（openrc modules 服务） |
| 防火墙 | 启用 nftables 服务（网关角色） | **不装**：容器非网关角色，无容器级防火墙需求（曾误启导致 Alpine 包默认规则断网） |

---

## sysctl 调优参数

与 Debian 版一致，写入 `/etc/sysctl.conf`（Alpine 启动加载路径），带 `# onekey-init` 标记头幂等：

- **网络**：`fq` + BBR、conntrack_max、`tcp_fin_timeout=15`、`tcp_tw_reuse=1`、缓冲区 16MB、端口范围 `1024 65535`
- **系统**：`swappiness=10`、`vfs_cache_pressure=50`

> LXC 内不可写参数（如 `nf_conntrack_max`，属宿主网络命名空间）自动跳过并提示，不中断。nf_conntrack 模块加载尝试写入 `/etc/modules`。

---

## 网络基础设施四件套部署顺序

本脚本 + `onekey-tailscale_alp` + `onekey-mosdns_alp` + `onekey-frpc_alp`，将网络基础服务从 Linux Gate（daed 所在机）分离：

```bash
./onekey-init_alp.sh            # ① 系统初始化（换源/工具/调优）
./onekey-tailscale_alp.sh       # ② tailscale + tailscale up 登录
./onekey-mosdns_alp.sh          # ③ mosdns (remote 上游 = tailnet VPS dnsmasq)
./onekey-frpc_alp.sh            # ④ frpc
```

---

## 许可证

本项目基于 [GPL-3.0](LICENSE) 协议。
