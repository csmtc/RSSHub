#!/bin/bash
# ============================================================
# RSSHub Termux 交叉编译脚本
# ============================================================
# 用途: 在 x86_64 Linux (WSL/Docker) 上编译 RSSHub for Termux (aarch64)
# 用法: ./build.sh
# 输出: ./output/rsshub-termux.tar.gz
#
# 依赖:
#   - Node.js 24+ (通过 nvm 安装)
#   - pnpm
#   - rsync, tar

set -e

# ============================================================
# 配置
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="$SCRIPT_DIR/output"
WORK_DIR="/tmp/rsshub-build-$$"

# CookieCloud 依赖
CRYPTO_JS_VERSION="latest"

# ============================================================
# 辅助函数
# ============================================================

log_info() {
    echo -e "\033[0;32m[INFO]\033[0m $1"
}

log_error() {
    echo -e "\033[0;31m[ERROR]\033[0m $1"
    exit 1
}

cleanup() {
    if [ -d "$WORK_DIR" ]; then
        rm -rf "$WORK_DIR"
    fi
}

trap cleanup EXIT

# ============================================================
# 检查依赖
# ============================================================

log_info "检查编译环境..."

if ! command -v node &> /dev/null; then
    log_error "Node.js 未安装，请先安装: nvm install 24"
fi

NODE_VERSION=$(node -v | sed 's/v//' | cut -d. -f1)
if [ "$NODE_VERSION" -lt 24 ]; then
    log_error "Node.js 版本过低 (当前: v$NODE_VERSION)，需要 v24+"
fi

if ! command -v pnpm &> /dev/null; then
    log_info "pnpm 未安装，正在通过 corepack 安装..."
    corepack enable
    corepack prepare pnpm@latest --activate
fi

log_info "Node.js $(node -v), pnpm $(pnpm -v)"

# ============================================================
# 准备工作目录
# ============================================================

log_info "准备工作目录: $WORK_DIR"

mkdir -p "$WORK_DIR"
mkdir -p "$OUTPUT_DIR"

# 复制源码 (排除不需要的文件)
log_info "复制源码..."
rsync -a \
    --exclude='.git' \
    --exclude='node_modules' \
    --exclude='build' \
    --exclude='dist' \
    "$SCRIPT_DIR/../../" "$WORK_DIR/"

log_info "源码大小: $(du -sh "$WORK_DIR" | cut -f1)"

# ============================================================
# 安装依赖
# ============================================================

cd "$WORK_DIR"

log_info "安装项目依赖..."
export PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=true
pnpm install --frozen-lockfile

log_info "安装 CookieCloud 依赖 (crypto-js)..."
pnpm add crypto-js --save-prod

# ============================================================
# 编译
# ============================================================

log_info "编译 RSSHub..."
npm run build

if [ ! -f "dist/index.mjs" ]; then
    log_error "编译失败: dist/index.mjs 不存在"
fi

log_info "编译成功: dist/index.mjs"

# ============================================================
# 打包 Termux 分发版本
# ============================================================

log_info "打包 Termux 分发版本..."

DIST_DIR="$WORK_DIR/rsshub-termux"
rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR/cookiecloud"
mkdir -p "$DIST_DIR/data"

# 复制编译产物
cp -a dist "$DIST_DIR/"
cp -a package.json "$DIST_DIR/"
cp -a node_modules "$DIST_DIR/"

# 复制 CookieCloud 插件
cp -a app/cookiecloud/* "$DIST_DIR/cookiecloud/"

# 创建启动脚本
cat > "$DIST_DIR/rsshub" << 'LAUNCHER'
#!/data/data/com.termux/files/usr/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# 加载环境变量
[ -f "$SCRIPT_DIR/data/env" ] && set -a && source "$SCRIPT_DIR/data/env" && set +a
[ -f "$SCRIPT_DIR/data/cookiecloud.env" ] && set -a && source "$SCRIPT_DIR/data/cookiecloud.env" && set +a

# 启动 RSSHub (通过 CookieCloud 入口)
exec node "$SCRIPT_DIR/cookiecloud/index.js" "$@"
LAUNCHER
chmod +x "$DIST_DIR/rsshub"

# 创建环境变量模板
cat > "$DIST_DIR/data/env.template" << 'ENV'
# RSSHub 环境变量配置
# 复制为 env 并修改: cp env.template env
export NODE_ENV=production
export NODE_OPTIONS=--max-http-header-size=32768
export PORT=1200
export LISTEN_INADDR_ANY=true
ENV

cat > "$DIST_DIR/data/cookiecloud.env.template" << 'CCENV'
# CookieCloud 配置
# 复制为 cookiecloud.env 并修改: cp cookiecloud.env.template cookiecloud.env
export COOKIE_CLOUD_HOST=http://127.0.0.1:8088
export COOKIE_CLOUD_UUID=your-uuid
export COOKIE_CLOUD_PASSWORD=your-password
export COOKIE_CLOUD_INTERVAL=3600
export COOKIE_CLOUD_DEBUG=true
CCENV

# 创建 sv 服务脚本模板
cat > "$DIST_DIR/data/rsshub.sv.run" << 'SVRUN'
#!/data/data/com.termux/files/usr/bin/sh
exec 2>&1

HOME_DIR=/data/data/com.termux/files/home
RSSHUB_DIR="$HOME_DIR/soft/RSSHub"
cd "$RSSHUB_DIR"

# 加载环境变量 (自动 export)
set -a
[ -f data/env ] && . data/env
[ -f data/cookiecloud.env ] && . data/cookiecloud.env
set +a

# 等待 CookieCloud API 就绪 (最多 30 秒)
echo "Waiting for CookieCloud API..."
i=0
while [ $i -lt 30 ]; do
    if curl -s -o /dev/null http://127.0.0.1:8088 2>/dev/null; then
        echo "CookieCloud API is ready"
        break
    fi
    sleep 1
    i=$((i + 1))
done

exec node cookiecloud/index.js
SVRUN

# 创建开机启动脚本模板
cat > "$DIST_DIR/data/start-rsshub.boot.sh" << 'BOOT'
#!/data/data/com.termux/files/usr/bin/bash
# Termux:Boot 开机启动脚本
# 安装位置: ~/.termux/boot/start-rsshub.sh

termux-wake-lock
sleep 2

export SVDIR=/data/data/com.termux/files/usr/var/service

# 先启动 CookieCloud
sv start cookiecloud-api
sleep 3

# 再启动 RSSHub
sv start rsshub
BOOT

# 创建安装脚本
cat > "$DIST_DIR/install.sh" << 'INSTALLER'
#!/bin/bash
# ============================================================
# RSSHub Termux 安装脚本
# ============================================================
# 用法: ./install.sh [--path /path/to/install]
# 默认安装路径: ~/soft/RSSHub

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_PATH="${1:-$HOME/soft/RSSHub}"

if [ "$1" = "--path" ]; then
    INSTALL_PATH="$2"
fi

echo "=========================================="
echo "  RSSHub for Termux 安装"
echo "=========================================="
echo "安装路径: $INSTALL_PATH"
echo ""

# 创建目录
mkdir -p "$INSTALL_PATH"
mkdir -p "$INSTALL_PATH/data/logs"

# 复制文件
echo "复制文件..."
cp -a "$SCRIPT_DIR"/* "$INSTALL_PATH/"
cp -a "$SCRIPT_DIR"/.[^.]* "$INSTALL_PATH/" 2>/dev/null || true

# 复制配置模板 (不覆盖已有配置)
if [ ! -f "$INSTALL_PATH/data/env" ]; then
    cp "$INSTALL_PATH/data/env.template" "$INSTALL_PATH/data/env"
    echo "创建配置: $INSTALL_PATH/data/env"
fi

if [ ! -f "$INSTALL_PATH/data/cookiecloud.env" ]; then
    cp "$INSTALL_PATH/data/cookiecloud.env.template" "$INSTALL_PATH/data/cookiecloud.env"
    echo "创建配置: $INSTALL_PATH/data/cookiecloud.env"
fi

echo ""
echo "=========================================="
echo "  安装完成!"
echo "=========================================="
echo ""
echo "后续步骤:"
echo "  1. 编辑配置文件:"
echo "     nano $INSTALL_PATH/data/env"
echo "     nano $INSTALL_PATH/data/cookiecloud.env"
echo ""
echo "  2. 手动启动测试:"
echo "     cd $INSTALL_PATH && ./rsshub"
echo ""
echo "  3. 配置 sv 服务 (可选):"
echo "     cp $INSTALL_PATH/data/rsshub.sv.run \\"
echo "        \$PREFIX/var/service/rsshub/run"
echo "     chmod +x \$PREFIX/var/service/rsshub/run"
echo ""
echo "  4. 配置开机自启 (可选):"
echo "     cp $INSTALL_PATH/data/start-rsshub.boot.sh \\"
echo "        ~/.termux/boot/start-rsshub.sh"
echo "     chmod +x ~/.termux/boot/start-rsshub.sh"
echo ""
INSTALLER
chmod +x "$DIST_DIR/install.sh"

# ============================================================
# 生成压缩包
# ============================================================

log_info "生成压缩包..."
cd "$WORK_DIR"
tar czf "$OUTPUT_DIR/rsshub-termux.tar.gz" --hard-dereference rsshub-termux/

log_info "=========================================="
log_info "  编译完成!"
log_info "=========================================="
log_info "输出文件: $OUTPUT_DIR/rsshub-termux.tar.gz"
log_info "文件大小: $(du -sh "$OUTPUT_DIR/rsshub-termux.tar.gz" | cut -f1)"
log_info ""
log_info "在 Termux 上安装:"
log_info "  1. 传输 rsshub-termux.tar.gz 到手机"
log_info "  2. tar xzf rsshub-termux.tar.gz"
log_info "  3. cd rsshub-termux && ./install.sh"