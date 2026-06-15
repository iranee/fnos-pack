#!/usr/bin/env bash
# =============================================================
# download.sh — 下载 Resilio Sync 二进制文件
# 来源: https://www.resilio.com/sync/download/
#
# 用法:
#   ./download.sh                 # 下载双架构 (x86 + arm)
#   ./download.sh --arch x86      # 仅 x86_64
#   ./download.sh --arch arm      # 仅 arm64
# =============================================================

set -e

WORKDIR="$(cd "$(dirname "$0")" && pwd)"

# ---- 下载地址（Resilio 官方 CDN，不区分版本号） ----
DOWNLOAD_URLS=(
    "x86|https://download-cdn.resilio.com/2.8.1.1390/linux/x64/0/resilio-sync_x64.tar.gz"
    "arm|https://download-cdn.resilio.com/2.8.1.1390/linux/arm64/0/resilio-sync_arm64.tar.gz"
)

# ---- 参数解析 ----
ARCH=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --arch)     ARCH="$2"; shift 2 ;;
        --arch=*)   ARCH="${1#*=}"; shift ;;
        --check)
            # CI 版本检测：输出 manifest 中的版本号（Resilio 无公开版本 API）
            MANIFEST_DIR="$(cd "$(dirname "$0")" && pwd)"
            VERSION=$(grep "^version" "$MANIFEST_DIR/manifest" 2>/dev/null | awk -F'=' '{print $2}' | tr -d ' ')
            echo "${VERSION:-unknown}"
            exit 0
            ;;
        -h|--help)
            echo "用法: $0 [--arch x86|arm]"
            echo ""
            echo "  默认下载双架构 (x86_64 + arm64)"
            echo "  Resilio Sync 从官方 CDN 下载最新稳定版"
            exit 0
            ;;
        -*) echo "[ERROR] 未知选项: $1"; exit 1 ;;
        *)  shift ;;
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

echo ""
echo "[INFO] 下载 Resilio Sync 二进制文件..."
echo "[INFO] 来源: https://www.resilio.com/sync/download/"

# ---- 架构映射 ----
get_local_dir() {
    case "$1" in
        x86) echo "x86_64" ;;
        arm) echo "arm64" ;;
    esac
}

get_download_url() {
    local target_arch="$1"
    for entry in "${DOWNLOAD_URLS[@]}"; do
        local a="${entry%%|*}"
        local u="${entry##*|}"
        [ "$a" = "$target_arch" ] && echo "$u" && return
    done
    echo ""
}

# ---- 下载并解压 ----
for arch in "${ARCH_LIST[@]}"; do
    LOCAL_DIR=$(get_local_dir "$arch")
    URL=$(get_download_url "$arch")

    [ -z "$URL" ] && { echo "[ERROR] 未找到 $arch 的下载地址"; exit 1; }

    echo ""
    echo "[INFO] ---- ${LOCAL_DIR} ----"
    echo "[INFO]   下载: ${URL}"

    # 清理旧文件
    rm -rf "${WORKDIR}/${LOCAL_DIR}"
    mkdir -p "${WORKDIR}/${LOCAL_DIR}"

    # 下载
    TMPFILE="/tmp/resilio-sync_${arch}.tar.gz"
    curl -fL --retry 3 --retry-delay 5 -o "$TMPFILE" "$URL" || {
        echo "[ERROR] 下载失败: $URL"
        exit 1
    }

    # 解压
    echo "[INFO]   解压..."
    tar -xzf "$TMPFILE" -C "${WORKDIR}/${LOCAL_DIR}/" 2>/dev/null || true

    # 如果有子目录，把二进制提到根目录
    find "${WORKDIR}/${LOCAL_DIR}" -mindepth 2 -name "rslsync" -type f \
        -exec mv {} "${WORKDIR}/${LOCAL_DIR}/" \; 2>/dev/null || true

    # 清理非二进制文件
    find "${WORKDIR}/${LOCAL_DIR}" -type f ! -name "rslsync" -delete 2>/dev/null || true
    find "${WORKDIR}/${LOCAL_DIR}" -mindepth 1 -type d -empty -delete 2>/dev/null || true

    rm -f "$TMPFILE"

    # 设置可执行权限
    chmod +x "${WORKDIR}/${LOCAL_DIR}/rslsync" 2>/dev/null || true

    # 验证
    echo "[INFO]   结果:"
    ls -lh "${WORKDIR}/${LOCAL_DIR}/"

    if [ ! -f "${WORKDIR}/${LOCAL_DIR}/rslsync" ]; then
        echo ""
        echo "[ERROR] ${LOCAL_DIR} 缺少 rslsync 二进制文件！"
        exit 1
    fi
done

echo ""
echo "[INFO] 完成! 下一步运行 build.sh 打包 fpk。"