#!/bin/bash
set -e

# =============================================================
# sync-cmd.sh — 从 template/cmd/ 同步通用文件到所有应用
# =============================================================
#
# 用法:
#   ./sync-cmd.sh              # 同步到所有含 manifest 的子目录
#   ./sync-cmd.sh fnos-gocron  # 仅同步指定应用
#
# 说明:
#   将 template/cmd/ 中的通用文件覆盖到各 app 的 cmd/ 目录。
#   不会覆盖 cmd/service-setup（应用专属文件）。
#
# =============================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$SCRIPT_DIR"
SHARED_CMD="$REPO_ROOT/template/cmd"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

[ -d "$SHARED_CMD" ] || error "缺少模板目录: template/cmd/"

# 通用文件列表（不包含 service-setup）
TEMPLATE_FILES=(
    main common installer
    install_init install_callback
    uninstall_init uninstall_callback
    upgrade_init upgrade_callback
    config_init config_callback
)

# 确定目标应用
if [ -n "$1" ]; then
    APPS=("$1")
    [ -f "$REPO_ROOT/apps/$1/manifest" ] || error "未找到应用: apps/$1/manifest"
else
    APPS=()
    for dir in "$REPO_ROOT/apps"/*/; do
        dir_name=$(basename "$dir")
        # 跳过 template、dist、.git 等非应用目录
        [ "$dir_name" = "template" ] && continue
        [ "$dir_name" = "dist" ] && continue
        [ "$dir_name" = ".git" ] && continue
        [ -f "$dir/manifest" ] && APPS+=("$dir_name")
    done
    [ ${#APPS[@]} -eq 0 ] && error "未找到任何应用目录"
fi

info "同步 template/cmd/ → ${#APPS[@]} 个应用"
echo ""

for app in "${APPS[@]}"; do
    APP_CMD="$REPO_ROOT/apps/$app/cmd"

    if [ ! -d "$APP_CMD" ]; then
        warn "  $app: 缺少 cmd/ 目录，跳过"
        continue
    fi

    echo -n "  $app: "
    count=0
    for f in "${TEMPLATE_FILES[@]}"; do
        if [ -f "$SHARED_CMD/$f" ]; then
            cp "$SHARED_CMD/$f" "$APP_CMD/$f"
            chmod +x "$APP_CMD/$f"
            count=$((count + 1))
        fi
    done
    echo "已同步 $count 个文件"
done

# 同步 wizard/uninstall
SHARED_WIZARD="$REPO_ROOT/template/wizard"
if [ -f "$SHARED_WIZARD/uninstall" ]; then
    echo ""
    info "同步 template/wizard/uninstall"
    for app in "${APPS[@]}"; do
        APP_WIZARD="$REPO_ROOT/apps/$app/wizard"
        if [ -d "$APP_WIZARD" ]; then
            cp "$SHARED_WIZARD/uninstall" "$APP_WIZARD/uninstall"
            echo "  $app: 已同步"
        fi
    done
fi

echo ""
info "同步完成！各应用的 cmd/service-setup 未被修改。"
