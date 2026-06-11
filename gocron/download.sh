#!/usr/bin/env bash
# =============================================================
# download.sh — 从 GitHub Release 下载 gocron 二进制文件
# 来源: https://github.com/gocronx-team/gocron/releases
#
# 用法:
#   ./download.sh           # 自动获取最新版本
#   ./download.sh 1.6.2     # 指定版本
#   ./download.sh --arch x86       # 仅 x86_64
#   ./download.sh --arch arm 1.6.2 # 仅 arm64，指定版本
# =============================================================

set -e

WORKDIR="$(cd "$(dirname "$0")" && pwd)"
GITHUB_REPO="gocronx-team/gocron"

# ---- 参数解析 ----
ARCH=""
VERSION=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --arch)     ARCH="$2"; shift 2 ;;
        --arch=*)   ARCH="${1#*=}"; shift ;;
        -h|--help)
            echo "用法: $0 [--arch x86|arm] [版本号]"
            echo ""
            echo "  默认下载双架构 (x86_64 + arm64)"
            echo "  版本号留空则自动获取最新 Release"
            exit 0
            ;;
        -*) echo "[ERROR] 未知选项: $1"; exit 1 ;;
        *)  VERSION="$1"; shift ;;
    esac
done

# ---- 确定架构列表 ----
if [ -z "$ARCH" ]; then
    ARCH_LIST=("x86" "arm")
else
    case "$ARCH" in
        x86|arm) ARCH_LIST=("$ARCH") ;;
        *) echo "[ERROR] 无效架构: $ARCH（必须是 x86 或 arm）"; exit 1 ;;
    esac
fi

# ---- 确定版本 ----
if [ -n "$VERSION" ]; then
    echo "[INFO] 使用指定版本: v${VERSION}"
else
    VERSION=$(curl -fsSL "https://api.github.com/repos/${GITHUB_REPO}/releases/latest" \
        | grep '"tag_name"' | head -1 | sed 's/.*"v\([^"]*\)".*/\1/')
    [ -n "$VERSION" ] || { echo "[ERROR] 无法获取最新版本号"; exit 1; }
    echo "[INFO] 最新版本: v${VERSION}"
fi

# ---- 下载基础 URL ----
# 格式: https://github.com/gocronx-team/gocron/releases/download/v1.6.2/gocron-1.6.2-linux-amd64.tar.gz
#       https://github.com/gocronx-team/gocron/releases/download/v1.6.2/gocron-node-linux-amd64.tar.gz
BASE_URL="https://github.com/${GITHUB_REPO}/releases/download/v${VERSION}"

echo ""
echo "[INFO] 下载 gocron v${VERSION} 二进制文件..."
echo "[INFO] 来源: ${GITHUB_REPO}"

# ---- 映射架构名称 ----
# x86 → amd64, arm → arm64
get_upstream_arch() {
    case "$1" in
        x86) echo "amd64" ;;
        arm) echo "arm64" ;;
    esac
}

get_local_dir() {
    case "$1" in
        x86) echo "x86_64" ;;
        arm) echo "arm64" ;;
    esac
}

# ---- 下载并解压 ----
for arch in "${ARCH_LIST[@]}"; do
    UPSTREAM_ARCH=$(get_upstream_arch "$arch")
    LOCAL_DIR=$(get_local_dir "$arch")

    echo ""
    echo "[INFO] ---- ${LOCAL_DIR} (${UPSTREAM_ARCH}) ----"

    # 清理旧文件
    rm -rf "${WORKDIR}/${LOCAL_DIR}"
    mkdir -p "${WORKDIR}/${LOCAL_DIR}"

    # 下载 gocron 主程序
    # 文件名: gocron-{VERSION}-linux-{ARCH}.tar.gz
    MAIN_URL="${BASE_URL}/gocron-${VERSION}-linux-${UPSTREAM_ARCH}.tar.gz"
    echo "[INFO]   下载 gocron: ${MAIN_URL}"
    curl -fsSL "$MAIN_URL" -o /tmp/gocron_main.tar.gz || {
        echo "[ERROR] 下载 gocron (${UPSTREAM_ARCH}) 失败"
        exit 1
    }

    # 下载 gocron-node
    # 文件名: gocron-node-linux-{ARCH}.tar.gz（无版本号）
    NODE_URL="${BASE_URL}/gocron-node-linux-${UPSTREAM_ARCH}.tar.gz"
    echo "[INFO]   下载 gocron-node: ${NODE_URL}"
    curl -fsSL "$NODE_URL" -o /tmp/gocron_node.tar.gz || {
        echo "[ERROR] 下载 gocron-node (${UPSTREAM_ARCH}) 失败"
        exit 1
    }

    # 解压
    echo "[INFO]   解压..."
    tar -xzf /tmp/gocron_main.tar.gz -C "${WORKDIR}/${LOCAL_DIR}/" 2>/dev/null || true
    tar -xzf /tmp/gocron_node.tar.gz -C "${WORKDIR}/${LOCAL_DIR}/" 2>/dev/null || true

    # 如果有子目录，把二进制提到根目录
    find "${WORKDIR}/${LOCAL_DIR}" -mindepth 2 -name "gocron" -type f \
        -exec mv {} "${WORKDIR}/${LOCAL_DIR}/" \; 2>/dev/null || true
    find "${WORKDIR}/${LOCAL_DIR}" -mindepth 2 -name "gocron-node" -type f \
        -exec mv {} "${WORKDIR}/${LOCAL_DIR}/" \; 2>/dev/null || true

    # 清理非二进制文件
    find "${WORKDIR}/${LOCAL_DIR}" -type f ! -name "gocron" ! -name "gocron-node" -delete 2>/dev/null || true
    find "${WORKDIR}/${LOCAL_DIR}" -mindepth 1 -type d -empty -delete 2>/dev/null || true

    rm -f /tmp/gocron_main.tar.gz /tmp/gocron_node.tar.gz

    # 验证
    echo "[INFO]   结果:"
    ls -lh "${WORKDIR}/${LOCAL_DIR}/"

    if [ ! -f "${WORKDIR}/${LOCAL_DIR}/gocron" ] || [ ! -f "${WORKDIR}/${LOCAL_DIR}/gocron-node" ]; then
        echo ""
        echo "[ERROR] ${LOCAL_DIR} 缺少二进制文件！请检查版本号。"
        exit 1
    fi
done

# ---- 更新 manifest 版本号 ----
if [ -f "${WORKDIR}/manifest" ]; then
    sed -i "s/^version.*=.*/version               = ${VERSION}/" "${WORKDIR}/manifest"
    echo ""
    echo "[INFO] manifest 版本已更新为: ${VERSION}"
fi

echo ""
echo "[INFO] 完成! 下一步运行 build.sh 打包 fpk。"
