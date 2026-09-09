#!/bin/sh
# ============================================================
# onekey-init_alp — Alpine Linux 系统初始化脚本
# 适用环境: Alpine Linux LXC (OpenRC)
# 功能: 换源 + 系统更新 + 基础工具 + nftables + chrony + 网络调优
# 与 onekey-init (Debian 直装版) 功能一致, 平台层适配 apk/OpenRC/musl
# 差异: 无 journald (busybox syslogd)、无 gai.conf (musl 默认 IPv4 优先)、无 exim
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
info "=== 1/8 替换 apk 源为阿里镜像 ==="
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
info "=== 2/8 系统更新 ==="
apk upgrade
info "  ✓ 系统已更新"

# =================== 3. 安装基础工具 ===================
# 与 Debian 版对齐: curl wget nano btop iproute2 nftables sudo ca-certificates unzip cron chrony
# 差异: cron → busybox crond (Alpine 内建, 稍后启用服务); tzdata 供时区设置
# 不装: git / vim / net-tools (与 Debian 版一致, 网关不需要)
info "=== 3/8 安装基础工具 ==="
apk add --no-cache -q \
  curl wget nano \
  btop \
  iproute2 nftables \
  sudo ca-certificates \
  unzip tzdata chrony
info "  ✓ 基础工具已安装"

# =================== 4. 启用 nftables ===================
info "=== 4/8 启用 nftables ==="
# Alpine nftables 包 OpenRC 服务读 /etc/nftables.nft; 空规则兜底
if [ ! -f /etc/nftables.nft ]; then
  echo "flush ruleset" > /etc/nftables.nft
fi
rc-update add nftables default 2>/dev/null || true
rc-service nftables start 2>/dev/null || warn "  nftables 启动失败 (检查 /etc/nftables.nft)"
info "  ✓ nftables 已启用（未写规则，按需添加）"

# =================== 5. 配置 chrony 时间同步 ===================
# Alpine 无 systemd-timesyncd (busybox ntpd 默认未运行), 直接启用 chrony
info "=== 5/8 配置时间同步 ==="
rc-update add chronyd default 2>/dev/null || true
rc-service chronyd start 2>/dev/null || warn "  chronyd 启动失败"
sleep 1
chronyc tracking 2>/dev/null | grep -E 'Stratum|System time' || true
info "  ✓ chrony 时间同步已启动"

# =================== 6. 网络性能调优 ===================
info "=== 6/8 网络性能调优 ==="
# IPv4 优先: Debian(glibc) 用 /etc/gai.conf; Alpine(musl) 无 gai.conf,
#   musl getaddrinfo 按 AF_INET → AF_INET6 顺序查询, 天然 IPv4 优先, 无需配置
info "  ✓ IPv4 优先: musl 内建行为, 无需 gai.conf"

# 网络参数写入 /etc/sysctl.conf (Alpine 启动加载路径; 幂等: 带标记头整块跳过)
NET_MARK="# onekey-init network tuning"
if grep -qF "$NET_MARK" /etc/sysctl.conf 2>/dev/null; then
  info "  - 网络参数已存在, 跳过写入"
else
  cat >> /etc/sysctl.conf << 'SYSEOF'

# onekey-init network tuning
# 网络性能优化
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
# 连接跟踪 (LXC 内不可写由宿主控制, 应用时跳过)
net.netfilter.nf_conntrack_max = 1048576
net.nf_conntrack_max = 1048576
# TIME_WAIT 优化
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_tw_reuse = 1
# 缓冲区增大（适合代理场景）
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216
# 端口范围（代理需要大量连接）
net.ipv4.ip_local_port_range = 1024 65535
# 其他优化
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_notsent_lowat = 16384
SYSEOF
  info "  ✓ 网络参数已写入 /etc/sysctl.conf"
fi

# nf_conntrack 开机加载: Alpine 用 /etc/modules (openrc modules 服务);
# LXC 无 CAP_SYS_MODULE 加载失败仅提示不中断
if ! grep -qxF nf_conntrack /etc/modules 2>/dev/null; then
  echo nf_conntrack >> /etc/modules
fi
modprobe nf_conntrack 2>/dev/null || warn "  提示: LXC 内无法加载内核模块 (宿主已加载则无影响)"

# 逐条应用 sysctl (纯 sh 逐行解析, 兼容 busybox; LXC 不可写参数跳过不中断)
set +e
while IFS= read -r line; do
  case "$line" in
    ""|\#*) continue ;;
  esac
  case "$line" in
    *=*)
      key=${line%%=*}; val=${line#*=}
      key=$(echo $key)   # 去首尾空白
      val=$(echo $val)   # 折叠连续空白为单 (适配 tcp_rmem 等多值参数)
      [ -n "$key" ] && { sysctl -w "$key=$val" &>/dev/null || warn "  跳过不可写参数: $key"; }
      ;;
  esac
done < /etc/sysctl.conf
set -e
info "  ✓ 网络参数已优化 (BBR + 缓冲区 + 端口范围)"

# =================== 7. 系统参数调优 ===================
info "=== 7/8 系统参数调优 ==="
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
set +e
sysctl -w vm.swappiness=10 &>/dev/null || warn "  跳过不可写参数: vm.swappiness"
sysctl -w vm.vfs_cache_pressure=50 &>/dev/null || warn "  跳过不可写参数: vm.vfs_cache_pressure"
set -e

# 设置时区 Asia/Shanghai (Alpine 无 timedatectl: 直接链接 zoneinfo, tzdata 已装)
if [ -f /usr/share/zoneinfo/Asia/Shanghai ]; then
  ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
  info "  ✓ 时区已设为 Asia/Shanghai"
else
  warn "  tzdata 缺失, 时区未设置"
fi
info "  ✓ 系统参数已优化 (swappiness=10)"

# =================== 8. 清理 ===================
info "=== 8/8 清理 ==="
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
echo "  拥塞控制: $(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo '默认')"
echo "  防火墙: nftables ($(rc-service nftables status >/dev/null 2>&1 && echo '运行中' || echo '未运行'))"
echo "  时间同步: $(chronyc tracking 2>/dev/null | grep -q Stratum && echo 'chrony ✓' || echo 'chrony')"
echo "  时区: $(readlink /etc/localtime 2>/dev/null | sed 's#.*/zoneinfo/##' || echo '未设置')"
echo ""
info "下一步：安装具体服务"
info "  sh <(wget -qO- https://raw.githubusercontent.com/guochan2019/onekey-tailscale_alp/main/onekey-tailscale_alp.sh)"
info "  sh <(wget -qO- https://raw.githubusercontent.com/guochan2019/onekey-mosdns_alp/main/onekey-mosdns_alp.sh)"
info "  sh <(wget -qO- https://raw.githubusercontent.com/guochan2019/onekey-frpc_alp/main/onekey-frpc_alp.sh)"
