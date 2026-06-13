#!/bin/bash
# =============================================================
# build.sh — 使用 fnpack 官方工具打包 fnOS .fpk
# =============================================================
#
# 用法:
#   从根目录:
#     ./build.sh fnos-gocron                 # 指定应用，双架构
#     ./build.sh fnos-gocron --arch x86      # 仅 x86
#     ./build.sh fnos-gocron 1.6.2           # 指定版本
#
#   从应用目录内:
#     ../../build.sh                         # 自动检测当前目录
#     ../../build.sh --arch arm              # 仅 arm
#     ../../build.sh 1.6.2                   # 指定版本
#
# 说明:
#   使用 fnOS 官方 fnpack 工具打包。
#   不指定 --arch 时自动为 x86 和 arm 各打一个 fpk。
#   fnpack 首次运行会自动下载到仓库根目录，之后复用。
#
# 应用目录结构要求:
#   apps/<app>/
#   ├── manifest
#   ├── cmd/          config/      wizard/       (框架文件)
#   ├── app/                                  (运行时资源)
#   ├── x86_64/       arm64/                    (各架构二进制)
#   └── ICON.PNG      ICON_256.PNG  *.sc        (可选)
#
# =============================================================

set -e

# ---- 路径 ----
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CWD="$(pwd)"

# ---- 颜色 ----
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# =============================================================
# 参数解析
# =============================================================
TARGET_APP=""
ARCH=""
VERSION=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --arch)     ARCH="$2"; shift 2 ;;
        --arch=*)   ARCH="${1#*=}"; shift ;;
        -h|--help)
            echo "用法:"
            echo "  从根目录:  $0 <应用目录> [--arch x86|arm] [版本号]"
            echo "  从应用内:  ../../$0 [--arch x86|arm] [版本号]"
            echo ""
            echo "示例:"
            echo "  $0 fnos-gocron                  # 双架构"
            echo "  $0 fnos-gocron --arch x86       # 仅 x86"
            echo "  $0 fnos-gocron 1.6.2            # 指定版本"
            echo "  ../../$0                         # 在应用目录内，自动检测"
            echo "  ../../$0 --arch arm              # 在应用目录内，仅 arm"
            exit 0
            ;;
        -*) error "未知选项: $1" ;;
        *)
            # 第一个非选项参数：如果是目录名就是应用，否则当版本号
            if [ -z "$TARGET_APP" ] && [ -d "$SCRIPT_DIR/apps/$1" ] && [ -f "$SCRIPT_DIR/apps/$1/manifest" ]; then
                TARGET_APP="$1"
            else
                VERSION="$1"
            fi
            shift
            ;;
    esac
done

# =============================================================
# 确定应用目录
# =============================================================
APPS_DIR="$SCRIPT_DIR/apps"

if [ -n "$TARGET_APP" ]; then
    # 从根目录指定: ./build.sh fnos-gocron
    APP_DIR="$APPS_DIR/$TARGET_APP"
elif [ -f "$CWD/manifest" ]; then
    # 在应用目录内: ../../build.sh
    APP_DIR="$CWD"
    TARGET_APP="$(basename "$CWD")"
else
    error "请指定应用目录，例如: $0 fnos-gocron\n  或在应用目录内运行: ../../$0"
fi

[ -f "$APP_DIR/manifest" ] || error "找不到 manifest: $APP_DIR/manifest"

# ---- 从 manifest 读取 appname ----
APP_NAME=$(grep "^appname" "$APP_DIR/manifest" | awk -F'=' '{print $2}' | tr -d ' ')
[ -n "$APP_NAME" ] || error "manifest 中缺少 appname"

# ---- 版本号 ----
if [ -z "$VERSION" ]; then
    VERSION=$(grep "^version" "$APP_DIR/manifest" | awk -F'=' '{print $2}' | tr -d ' ')
    [ -n "$VERSION" ] || error "无法从 manifest 读取版本号"
fi

# ---- 架构列表 ----
if [ -z "$ARCH" ]; then
    BUILD_LIST=("x86" "arm")
else
    case "$ARCH" in
        x86|arm) BUILD_LIST=("$ARCH") ;;
        *) error "无效架构: $ARCH（必须是 x86 或 arm）" ;;
    esac
fi

info "应用: $APP_NAME v${VERSION} ($TARGET_APP)"
info "构建: ${BUILD_LIST[*]}"

# =============================================================
# fnpack 工具（放在仓库根目录，所有应用共享）
# =============================================================
FNPACK_VERSION="1.0.4"
FNPACK_BIN="$SCRIPT_DIR/fnpack"

if [ ! -x "$FNPACK_BIN" ]; then
    FNPACK_URL="https://static2.fnnas.com/fnpack/fnpack-${FNPACK_VERSION}-linux-amd64"
    info "下载 fnpack v${FNPACK_VERSION}..."
    curl -fsSL "$FNPACK_URL" -o "$FNPACK_BIN" || error "下载 fnpack 失败: $FNPACK_URL"
    chmod +x "$FNPACK_BIN"
    info "fnpack 已就绪"
else
    info "使用本地 fnpack"
fi

# =============================================================
# 通用清理：删除 app/ 下从架构目录复制过来的临时文件
# （保留 bin/ 和 ui/ 子目录中的文件）
# =============================================================
cleanup_bin() {
    find "$APP_DIR/app" -maxdepth 1 -type f -executable \
        ! -path "*/bin/*" ! -path "*/ui/*" -delete 2>/dev/null || true
}

# =============================================================
# 构建函数
# =============================================================
do_build() {
    local PLATFORM="$1"

    echo ""
    info "=========================================="
    info "  fnpack build: $APP_NAME v${VERSION} ($PLATFORM)"
    info "=========================================="

    # 清理上一次残留
    cleanup_bin

    # 复制对应架构二进制到 app/
    local BIN_ARCH_DIR
    case "$PLATFORM" in
        x86) BIN_ARCH_DIR="x86_64" ;;
        arm) BIN_ARCH_DIR="arm64"  ;;
    esac
    local BIN_DIR="$APP_DIR/$BIN_ARCH_DIR"
    [ -d "$BIN_DIR" ] || error "架构目录不存在: $BIN_DIR（请先运行 download.sh）"
    [ "$(ls -A "$BIN_DIR" 2>/dev/null)" ] || error "架构目录为空: $BIN_DIR"

    cp "$BIN_DIR/"* "$APP_DIR/app/" 2>/dev/null || true
    chmod +x "$APP_DIR/app/"* 2>/dev/null || true
    info "  已复制 $BIN_ARCH_DIR/ → app/"

    # 更新 manifest
    sed -i "s/^version.*=.*/version               = ${VERSION}/" "$APP_DIR/manifest"
    sed -i "s/^platform.*=.*/platform              = ${PLATFORM}/" "$APP_DIR/manifest"

    # fnpack build
    cd "$APP_DIR"
    "$FNPACK_BIN" build --directory "$APP_DIR"

    # 移动输出文件
    local SOURCE_FPK="$APP_DIR/${APP_NAME}.fpk"
    [ -f "$SOURCE_FPK" ] || error "fnpack 未生成 fpk 文件"

    local OUTPUT_DIR="$APP_DIR/dist"
    mkdir -p "$OUTPUT_DIR"

    local FPK_NAME="fnos-${APP_NAME}_${PLATFORM}_v${VERSION}.fpk"
    mv "$SOURCE_FPK" "$OUTPUT_DIR/$FPK_NAME"

    info "  完成: $FPK_NAME ($(du -h "$OUTPUT_DIR/$FPK_NAME" | cut -f1))"
    BUILT_FILES+=("$FPK_NAME")

    # 清理
    cleanup_bin
}

# =============================================================
# 主流程
# =============================================================
OUTPUT_DIR="$APP_DIR/dist"
mkdir -p "$OUTPUT_DIR"

BUILT_FILES=()

for arch in "${BUILD_LIST[@]}"; do
    do_build "$arch"
done

# 恢复 manifest 原始 platform
if [ -z "$ARCH" ]; then
    sed -i "s/^platform.*=.*/platform              = x86/" "$APP_DIR/manifest"
fi

# =============================================================
# 汇总
# =============================================================
echo ""
info "=========================================="
info "  构建完成!"
info "=========================================="
info "  应用: $APP_NAME ($TARGET_APP)"
info "  版本: v${VERSION}"
for f in "${BUILT_FILES[@]}"; do
    info "  文件: $f ($(du -h "$OUTPUT_DIR/$f" | cut -f1))"
done
info "  输出: $OUTPUT_DIR"
info "=========================================="
