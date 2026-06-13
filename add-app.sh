#!/bin/bash
set -e

# =============================================================
# add-app.sh — 创建新的 fnOS 应用模板
# =============================================================
#
# 用法: ./add-app.sh <appname> <display_name> <port> [maintainer] [maintainer_url]
#
# 示例:
#   ./add-app.sh gocron "Gocron 定时任务" 54920 gocron https://github.com/iranee/fnos-pack
#
# 说明:
#   从 template/cmd/ 和 template/wizard/ 复制通用模板，
#   生成一个完整的 fnOS 应用目录结构。
#   每个 app 的 cmd/ 目录包含所有文件（自包含），
#   只需修改 cmd/service-setup 和应用专属文件。
#
# =============================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$SCRIPT_DIR"
SHARED_DIR="$REPO_ROOT/template"

# ---- 参数 ----
APPNAME="$1"
DISPLAY_NAME="$2"
PORT="$3"
MAINTAINER="${4:-TODO}"
MAINTAINER_URL="${5:-TODO}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

[ -z "$APPNAME" ] && error "用法: $0 <appname> <display_name> <port> [maintainer] [maintainer_url]"
[ -z "$DISPLAY_NAME" ] && error "用法: $0 <appname> <display_name> <port>"
[ -z "$PORT" ] && error "用法: $0 <appname> <display_name> <port>"

APP_DIR="$REPO_ROOT/apps/$APPNAME"
if [ -d "$APP_DIR" ]; then
    # 允许空目录或只有少量文件的情况
    file_count=$(find "$APP_DIR" -mindepth 1 -type f 2>/dev/null | wc -l)
    [ "$file_count" -gt 5 ] && error "目录已存在且非空: $APP_DIR ($file_count 个文件)"
    warn "目录已存在（$file_count 个文件），将合并写入"
fi

# ---- 检查模板源 ----
[ -d "$SHARED_DIR/cmd" ] || error "缺少模板目录: template/cmd/"

info "创建应用: $APPNAME ($DISPLAY_NAME) 端口 $PORT"
echo ""

# =============================================================
# 创建目录结构
# =============================================================
mkdir -p "$APP_DIR"/{cmd,config,wizard,app/bin,app/ui/images}

info "  目录结构已创建"

# =============================================================
# 从 template/ 复制通用文件
# =============================================================

# cmd/ — 通用框架文件（除 service-setup）
for f in main common installer \
         install_init install_callback \
         uninstall_init uninstall_callback \
         upgrade_init upgrade_callback \
         config_init config_callback; do
    cp "$SHARED_DIR/cmd/$f" "$APP_DIR/cmd/$f"
    chmod +x "$APP_DIR/cmd/$f"
done

# wizard/uninstall — 通用卸载向导
cp "$SHARED_DIR/wizard/uninstall" "$APP_DIR/wizard/uninstall"

info "  已从 template/ 复制通用模板"

# =============================================================
# 生成应用专属文件
# =============================================================

# ---- manifest ----
cat > "$APP_DIR/manifest" << EOF
appname               = $APPNAME
version               = 0.0.0
display_name          = "$DISPLAY_NAME"
desc                  = "TODO: 应用描述"
platform              = x86
source                = thirdparty
desktop_uidir         = ui
desktop_applaunchname = ${APPNAME}.Application
service_port          = $PORT
maintainer            = $MAINTAINER
maintainer_url        = $MAINTAINER_URL
distributor           = bbis
distributor_url       = https://github.com/iranee/fnos-pack
checksum              = 
EOF

# ---- cmd/service-setup（从模板复制）----
TEMPLATE_SVC="$SHARED_DIR/cmd/service-setup.template"
if [ -f "$TEMPLATE_SVC" ]; then
    cp "$TEMPLATE_SVC" "$APP_DIR/cmd/service-setup"
    sed -i "s/pkill -x \"TODO\"/pkill -x \"${APPNAME}\"/g" "$APP_DIR/cmd/service-setup"
    sed -i "s/pkill -9 -x \"TODO\"/pkill -9 -x \"${APPNAME}\"/g" "$APP_DIR/cmd/service-setup"
    chmod +x "$APP_DIR/cmd/service-setup"
else
    warn "  缺少模板: template/cmd/service-setup.template，跳过 service-setup"
fi

# ---- app/bin/{appname}-server ----
cat > "$APP_DIR/app/bin/${APPNAME}-server" << EOF
#!/bin/sh
APP_DIR="\${TRIM_APPDEST}"
APP_DATA_DIR="\$1"

export HOME="\$APP_DATA_DIR"

cd "\$APP_DATA_DIR" || exit 1
# TODO: 替换为实际的启动命令
# exec "\$APP_DIR/your-binary" web
EOF
chmod +x "$APP_DIR/app/bin/${APPNAME}-server"

# ---- config/privilege ----
cat > "$APP_DIR/config/privilege" << EOF
{
    "defaults": {
        "run-as": "package"
    },
    "username": "$APPNAME",
    "groupname": "$APPNAME"
}
EOF

# ---- .sc 端口转发配置 ----
SC_NAME=$(echo "$DISPLAY_NAME" | tr -d ' ')
cat > "$APP_DIR/${SC_NAME}.sc" << EOF
[${SC_NAME}]
title="$DISPLAY_NAME"
desc="$DISPLAY_NAME Web UI"
port_forward="yes"
src.ports="${PORT}/tcp"
dst.ports="${PORT}/tcp"
EOF

# ---- config/resource（含 port-config 指向 .sc 文件）----
cat > "$APP_DIR/config/resource" << EOF
{
    "port-config": {
        "protocol-file": "${SC_NAME}.sc"
    },
    "data-share": {
        "shares": [
            {
                "name": "$DISPLAY_NAME",
                "permission": {
                    "rw": [
                        "$APPNAME"
                    ]
                }
            }
        ]
    },
    "systemd-unit": {
    }
}
EOF

# ---- app/ui/config ----
cat > "$APP_DIR/app/ui/config" << EOF
{
    ".url": {
        "${APPNAME}.Application":
        {
            "title": "$DISPLAY_NAME",
            "desc": "$DISPLAY_NAME",
            "icon": "images/{0}.png",
            "type": "url",
            "port": "$PORT",
            "protocol": "http",
            "url": "/",
            "allUsers": true
        }
    }
}
EOF

# ---- wizard/install（从模板复制）----
TEMPLATE_INSTALL="$SHARED_DIR/wizard/install.template"
if [ -f "$TEMPLATE_INSTALL" ]; then
    cp "$TEMPLATE_INSTALL" "$APP_DIR/wizard/install"
    sed -i "s/DISPLAY_NAME/${DISPLAY_NAME}/g" "$APP_DIR/wizard/install"
    sed -i "s/PORT/${PORT}/g" "$APP_DIR/wizard/install"
else
    warn "  缺少模板: template/wizard/install.template，跳过 wizard/install"
fi

info "  应用专属文件已生成"

# =============================================================
# 汇总
# =============================================================
echo ""
info "=========================================="
info "  应用模板创建完成!"
info "=========================================="
info "  目录: $APP_DIR"
echo ""
info "  下一步需要修改的文件:"
echo ""
info "  [必须] cmd/service-setup    — 修改 SERVICE_COMMAND、进程名和生命周期钩子"
info "  [必须] app/bin/${APPNAME}-server — 填写实际启动命令"
info "  [必须] manifest             — 填写 desc 描述"
info "  [必须] wizard/install       — 填写安装说明"
info "  [必须] ICON.PNG / ICON_256.PNG — 放入应用图标"
info "  [可选] app/ui/images/64.png  — 放入 UI 小图标"
info "  [可选] download.sh          — 如需下载上游二进制，创建此脚本"
echo ""
info "  模板说明:"
info "  cmd/ 通用文件来自 template/cmd/ 模板（勿修改）"
info "  cmd/service-setup 从 template/cmd/service-setup.template 生成"
info "  每个 app 只需定制 service-setup 和应用专属文件"
info "=========================================="
