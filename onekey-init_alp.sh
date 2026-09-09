#!/bin/sh
# ============================================================
# onekey-init_alp — Alpine Linux 系统初始化脚本
# 适用环境: Alpine Linux LXC (OpenRC)
# 功能: 换源 + 系统更新 + 基础工具 + 时区
# 与 onekey-init (Debian 直装版) 按容器角色裁剪, 平台层适配 apk/OpenRC/musl
# 裁剪依据 (2026-09-09 实测/实证):
#   - nftables/网络调优/BBR: 容器非网关角色, 无流量转发需求
#   - chrony: LXC 共享宿主内核时钟, 无实际调钟权 → 时间同步归宿主
#   - swappiness/vfs 写入: 宿主全局参数, LXC 内永不生效
#   - unzip/wget/btop: unzip 由 mosdns_alp 自装; wget busybox 自带; btop 轻服务容器无监控需求
#   - 无 journald/无 syslogd init/无 exim: 对应清理步骤整步无操作
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
info "=== 1/3 替换 apk 源为阿里镜像 ==="
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
info "=== 2/3 系统更新 ==="
apk upgrade
info "  ✓ 系统已更新"

# =================== 3. 安装基础工具 + 时区 ===================
# 工具清单: curl(脚本 API 查询) nano(唯一编辑器) iproute2(网络诊断 ss/ip)
#           sudo(用户指定保留) ca-certificates(https 必需) tzdata(时区)
# 不装: git/vim/net-tools/btop/unzip/wget (unzip 由 mosdns_alp 自装, wget busybox 自带)
# 不装: chrony (LXC 共享宿主时钟无调钟权, 时间同步归宿主)
info "=== 3/3 安装基础工具 ==="
apk add --no-cache -q \
  curl nano iproute2 sudo ca-certificates tzdata
info "  ✓ 基础工具已安装"

# 设置时区 Asia/Shanghai (Alpine 无 timedatectl: 直接链接 zoneinfo)
if [ -f /usr/share/zoneinfo/Asia/Shanghai ]; then
  ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
  info "  ✓ 时区已设为 Asia/Shanghai"
else
  warn "  tzdata 缺失, 时区未设置"
fi

# =================== 验证 ===================
echo ""
info "========== 初始化完成 =========="
echo ""
echo "  $(grep -c processor /proc/cpuinfo 2>/dev/null) vCPU / $(free -h 2>/dev/null | awk '/^Mem:/{print $2}') RAM"
echo "  内核: $(uname -r)"
echo "  时区: $(readlink /etc/localtime 2>/dev/null | sed 's#.*/zoneinfo/##' || echo '未设置')"
echo ""
info "下一步：安装具体服务"
info "  sh <(wget -qO- https://raw.githubusercontent.com/guochan2019/onekey-tailscale_alp/main/onekey-tailscale_alp.sh)"
info "  sh <(wget -qO- https://raw.githubusercontent.com/guochan2019/onekey-mosdns_alp/main/onekey-mosdns_alp.sh)"
info "  sh <(wget -qO- https://raw.githubusercontent.com/guochan2019/onekey-frpc_alp/main/onekey-frpc_alp.sh)"
