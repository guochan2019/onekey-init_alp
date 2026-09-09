#!/bin/sh
# ============================================================
# onekey-init_alp — Alpine Linux 系统初始化脚本
# 适用环境: Alpine Linux LXC (OpenRC)
# 功能: 换源 + 系统更新 + 基础工具 + chrony + 系统参数/时区
# 与 onekey-init (Debian 直装版) 功能一致, 平台层适配 apk/OpenRC/musl
# 差异: 无 journald (busybox syslogd)、无 gai.conf (musl 默认 IPv4 优先)、无 exim、
#       不装 nftables/不做网络调优 (容器非网关角色, 无流量转发需求; Debian 网关版才有)
# ============================================================
set -e

trap 'echo -e "\033[0;31m[ERROR] 脚本执行失败，请检查:\033[0m
  - 网络连接
  - 是否以 root 运行" >&2' ERR

# ---------- 彩色输出 (busybox echo 支持 -e) ----------
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
err()   { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# ---------- 检测 root ----------
if [ "$(id -u)" -ne 0 ]; then
  err "请以 root 用户运行 (当前非 root)"
fi

# ---------- 检测系统 ----------
if [ -f /etc/os-release ]; then
  . /etc/os-release
fi
[ "$ID" = "alpine" ] || warn "  非 Alpine 系统 (当前: ${ID:-未知}), 脚本按 apk/OpenRC 语义运行"

echo ""
echo "========================================"
echo "  Alpine Linux 系统初始化 (${VERSION_ID:-?})"
echo "========================================"
echo ""

# =================== 1. 替换国内源 ===================
# Alpine 仓库文件 /etc/apk/repositories 每行一个仓库, 形如:
#   https://dl-cdn.alpinelinux.org/alpine/v3.22/main
# 做法: 备份原文件 → 按原文件版本号重建为阿里镜像 main + community 两行
REPOS_FILE="/etc/apk/repositories"
info "=== 1/6 替换 apk 源为阿里镜像 ==="
cp "$REPOS_FILE" "${REPOS_FILE}.bak"
info "  ✓ 已备份原文件: ${REPOS_FILE}.bak"

# 从原文件提取版本段 (vX.Y), 提取失败则跳过换源 (保持官方源可用)
ALP_VER=$(grep -oE '/alpine/v[0-9]+\.[0-9]+/' "$REPOS_FILE" 2>/dev/null | head -1 | sed 's#/alpine/##;s#/##')
if [ -n "$ALP_VER" ]; then
  cat > "$REPOS_FILE" << REPOEOF
https://mirrors.aliyun.com/alpine/${ALP_VER}/main
https://mirrors.aliyun.com/alpine/${ALP_VER}/community
REPOEOF
  info "  ✓ 已写入阿里镜像 (${ALP_VER}/main + community)"
else
  warn "  无法识别 Alpine 版本号, 跳过换源 (沿用官方源)"
fi
apk update
info "  ✓ apk 源已就绪"

# =================== 2. 系统更新 ===================
info "=== 2/6 系统更新 ==="
apk upgrade
info "  ✓ 系统已更新"

# =================== 3. 安装基础工具 ===================
# 与 Debian 版对齐: curl wget nano btop iproute2 sudo ca-certificates unzip cron chrony
# 差异: cron → busybox crond (Alpine 内建, 稍后启用服务); tzdata 供时区设置;
#       nftables 不装 (容器非网关角色, 无容器级防火墙需求)
# 不装: git / vim / net-tools (与 Debian 版一致, 网关不需要)
info "=== 3/6 安装基础工具 ==="
apk add --no-cache -q \
  curl wget nano \
  btop \
  iproute2 \
  sudo ca-certificates \
  unzip tzdata chrony
info "  ✓ 基础工具已安装"

# =================== 4. 配置 chrony 时间同步 ===================
# Alpine 无 systemd-timesyncd (busybox ntpd 默认未运行), 直接启用 chrony
info "=== 4/6 配置时间同步 ==="
rc-update add chronyd default 2>/dev/null || true
rc-service chronyd start 2>/dev/null || warn "  chronyd 启动失败"
sleep 1
chronyc tracking 2>/dev/null | grep -E 'Stratum|System time' || true
info "  ✓ chrony 时间同步已启动"

# =================== 5. 系统参数调优 ===================
info "=== 5/6 系统参数调优 ==="
SYS_MARK="# onekey-init system tuning"
if grep -qF "$SYS_MARK" /etc/sysctl.conf 2>/dev/null; then
  info "  - 系统参数已存在, 跳过写入"
else
  cat >> /etc/sysctl.conf << 'SYSEOF'

# onekey-init system tuning
vm.swappiness = 10
vm.vfs_cache_pressure = 50
SYSEOF
fi
# vm.* 为宿主全局参数: LXC 内不可调属预期 (|| true 豁免 busybox ash 的 ERR trap; 写入保留, 物理机/特权容器生效)
sysctl -w vm.swappiness=10 >/dev/null 2>&1 || true
sysctl -w vm.vfs_cache_pressure=50 >/dev/null 2>&1 || true
if [ "$(cat /proc/sys/vm/swappiness 2>/dev/null)" = "10" ]; then
  info "  ✓ swappiness=10 已生效"
else
  info "  - swappiness/vfs 为宿主全局参数, 容器内不可调属预期 (配置已写入, 物理机/特权容器生效)"
fi

# 设置时区 Asia/Shanghai (Alpine 无 timedatectl: 直接链接 zoneinfo, tzdata 已装)
if [ -f /usr/share/zoneinfo/Asia/Shanghai ]; then
  ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
  info "  ✓ 时区已设为 Asia/Shanghai"
else
  warn "  tzdata 缺失, 时区未设置"
fi
info "  ✓ 系统参数已优化 (swappiness=10)"

# =================== 6. 清理 ===================
info "=== 6/6 清理 ==="
# Alpine 无 journald: 日志由 busybox syslogd 管理 (/var/log/messages)
# 启用 syslogd 并限制循环大小 (busybox syslogd -S 单位 KB; conf 惯例变量 SYSLOGD_OPTS)
if [ -f /etc/init.d/syslogd ]; then
  rc-update add syslogd default 2>/dev/null || true
  rc-service syslogd start 2>/dev/null || true
  # 写入循环上限 4MB (幂等追加; 若 init 脚本不支持该变量则静默无害, 仅不轮转)
  grep -q '^SYSLOGD_OPTS=' /etc/conf.d/syslogd 2>/dev/null || echo 'SYSLOGD_OPTS="-S 4096"' >> /etc/conf.d/syslogd
  # 配置改动需重启服务生效
  rc-service syslogd restart 2>/dev/null || true
  info "  ✓ syslogd 已启用 (循环上限 4MB, 配置 /etc/conf.d/syslogd)"
else
  info "  - 无 syslogd init 脚本, 跳过 (Alpine 无 journald, 服务日志各自落盘)"
fi
# Alpine 无 exim/MTA 依赖问题 (cron 不需要邮件传输)
# 清理 apk 下载缓存 (对齐 autoclean)
rm -rf /var/cache/apk/* 2>/dev/null || true
info "  ✓ 清理完成 (apk 缓存已清)"

# =================== 验证 ===================
echo ""
info "========== 初始化完成 =========="
echo ""
echo "  $(grep -c processor /proc/cpuinfo 2>/dev/null) vCPU / $(free -h 2>/dev/null | awk '/^Mem:/{print $2}') RAM"
echo "  内核: $(uname -r)"
echo "  时间同步: $(chronyc tracking 2>/dev/null | grep -q Stratum && echo 'chrony ✓' || echo 'chrony')"
echo "  时区: $(readlink /etc/localtime 2>/dev/null | sed 's#.*/zoneinfo/##' || echo '未设置')"
echo ""
info "下一步：安装具体服务"
info "  sh <(wget -qO- https://raw.githubusercontent.com/guochan2019/onekey-tailscale_alp/main/onekey-tailscale_alp.sh)"
info "  sh <(wget -qO- https://raw.githubusercontent.com/guochan2019/onekey-mosdns_alp/main/onekey-mosdns_alp.sh)"
info "  sh <(wget -qO- https://raw.githubusercontent.com/guochan2019/onekey-frpc_alp/main/onekey-frpc_alp.sh)"
