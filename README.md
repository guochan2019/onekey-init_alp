# onekey-init_alp

一键 **Alpine Linux 系统初始化**（换源 + 系统更新 + 基础工具 + 时区）。

> 与 [onekey-init](https://github.com/guochan2019/onekey-init)（Debian 网关版）同源，按 **Alpine LXC 容器服务角色**裁剪，平台层适配 **apk + OpenRC + musl**。

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

## 初始化流程（3 步）

| 步骤 | 说明 |
|------|------|
| 1/3 | 替换 apk 源为阿里镜像（`/etc/apk/repositories` 备份 `.bak`，按原版本号重建 main + community 两行） |
| 2/3 | 系统更新（`apk upgrade`） |
| 3/3 | 安装基础工具 + 设置时区 Asia/Shanghai |

安装工具清单（6 包）：`curl nano iproute2 sudo ca-certificates tzdata`

---

## 与 Debian 网关版差异（裁剪依据）

| 项 | Debian 网关版 | Alpine 容器版 | 依据（实证） |
|----|-----------|-----------|------|
| 源 | deb822 阿里源 | apk 阿里镜像（版本号自适应） | — |
| 工具 | curl wget nano btop iproute2 nftables sudo ca-certificates unzip cron chrony | curl nano iproute2 sudo ca-certificates tzdata | unzip 由 mosdns_alp 自装；wget busybox 自带；btop 轻服务容器无监控需求 |
| nftables | 启用（网关防火墙） | **不装** | 容器非网关角色；曾误启导致 Alpine 包默认规则断网 |
| 网络调优/BBR | BBR + 缓冲 + 端口范围 | **不做** | 容器不转发流量，无收益 |
| chrony | 时间同步 | **不装** | LXC 共享宿主内核时钟、容器内无实际调钟权 → 时间同步归宿主（PVE 宿主需配 NTP） |
| swappiness/vfs | 写入生效 | **不写** | 宿主全局参数，LXC 内永不生效 |
| 日志限制 | journald 50M | 无对应 | Alpine 无 journald/syslogd init，无日志膨胀问题 |
| 邮件清理 | purge exim4 | 无对应 | Alpine 无 MTA |
| 时区 | timedatectl | zoneinfo 链接（tzdata） | Alpine 无 timedatectl |

---

## 四件套部署顺序（网络基础设施强绑同一 Alpine LXC）

本脚本 + `onekey-tailscale_alp` + `onekey-mosdns_alp` + `onekey-frpc_alp`，将网络基础服务从 Linux Gate（daed 所在机）分离，避免 daed 故障时连带挂机：

```bash
./onekey-init_alp.sh            # ① 系统初始化（换源/工具/时区）
./onekey-tailscale_alp.sh       # ② tailscale + tailscale up 登录
./onekey-mosdns_alp.sh          # ③ mosdns (remote 上游 = tailnet VPS dnsmasq)
./onekey-frpc_alp.sh            # ④ frpc
```

三个服务均以 OpenRC 托管、`supervise-daemon` 崩溃自动拉起；各自独立，卸载互不影响。

---

## 许可证

本项目基于 [GPL-3.0](LICENSE) 协议。
