# RSSHub 在 Termux 环境交叉编译安装过程记录

## 概述

本文档记录了在 Windows 环境下通过 WSL (Windows Subsystem for Linux) 交叉编译 RSSHub 并安装到 Android Termux 的完整过程。

**环境信息:**
- 主机: Windows 11 + WSL2 (Ubuntu 24.04)
- 目标设备: Xiaomi K60 (Android 13, aarch64)
- Termux SSH: 已配置 SSH 连接到手机
- Node.js: v24.18.1 (通过 nvm 安装)

---

## 第一阶段: 环境准备

### 1.1 安装 Node.js 24

```bash
# 在 WSL 中安装 nvm
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash

# 安装 Node.js 24
source ~/.nvm/nvm.sh
nvm install 24
nvm use 24

# 验证
node --version  # v24.18.1
npm --version   # 11.16.0
```

### 1.2 克隆 RSSHub 仓库

```bash
cd /mnt/c/SoftwareGreen/amuse/RSSHub
```

---

## 第二阶段: 交叉编译

### 2.1 准备工作目录

由于 WSL 访问 `/mnt/c` 性能较差，使用 `/tmp` 目录:

```bash
# 复制源码到 WSL 原生文件系统
rsync -a --exclude='.git' --exclude='node_modules' --exclude='build' --exclude='dist' \
    /mnt/c/SoftwareGreen/amuse/RSSHub/ /tmp/rsshub-work/

cd /tmp/rsshub-work
```

### 2.2 安装依赖

```bash
# 跳过浏览器下载
export PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=true

# 安装项目依赖
pnpm install --frozen-lockfile

# 安装 CookieCloud 依赖
pnpm add crypto-js --save-prod
```

**耗时:** 约 22 秒

### 2.3 编译

```bash
npm run build
```

**输出:**
```
dist/index.mjs          # 主入口
dist/config-*.mjs       # 配置模块
dist/routes-*.mjs       # 路由模块 (约 3700+ 个)
```

**耗时:** 约 46 秒

### 2.4 打包 Termux 分发版本

```bash
DIST=/tmp/rsshub-termux
mkdir -p $DIST/cookiecloud $DIST/data

# 复制必要文件
cp -a dist $DIST/
cp -a package.json $DIST/
cp -a node_modules $DIST/
cp -a app/cookiecloud/* $DIST/cookiecloud/

# 创建启动脚本
cat > $DIST/rsshub << 'EOF'
#!/data/data/com.termux/files/usr/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"
[ -f "$SCRIPT_DIR/data/env" ] && set -a && source "$SCRIPT_DIR/data/env" && set +a
[ -f "$SCRIPT_DIR/data/cookiecloud.env" ] && set -a && source "$SCRIPT_DIR/data/cookiecloud.env" && set +a
exec node "$SCRIPT_DIR/cookiecloud/index.js" "$@"
EOF
chmod +x $DIST/rsshub
```

### 2.5 生成压缩包

```bash
cd /tmp
tar czf rsshub-termux.tar.gz --hard-dereference rsshub-termux/
```

**最终大小:** 190MB (压缩后), 855MB (解压后)

---

## 第三阶段: 传输到手机

### 3.1 复制到 Windows

```bash
cp /tmp/rsshub-termux.tar.gz /mnt/c/tmp/
```

### 3.2 通过 SCP 传输到手机

```bash
scp /mnt/c/tmp/rsshub-termux.tar.gz K60:~/rsshub-termux.tar.gz
```

**耗时:** 约 7 秒

---

## 第四阶段: 在 Termux 上安装

### 4.1 SSH 连接到手机

```bash
ssh K60
```

### 4.2 解压

```bash
cd ~
tar xzf rsshub-termux.tar.gz
```

**注意:** 使用 `--no-hard-links` 选项避免权限问题 (Termux tar 不支持此选项，但新版压缩包已处理)

### 4.3 安装到指定目录

```bash
# 创建目标目录
mkdir -p ~/soft/RSSHub/data/logs

# 复制文件
cp -a rsshub-termux/* ~/soft/RSSHub/
```

### 4.4 配置环境变量

创建 `~/soft/RSSHub/data/env`:

```bash
export NODE_ENV=production
export NODE_OPTIONS=--max-http-header-size=32768
export PORT=1200
export LISTEN_INADDR_ANY=true
```

创建 `~/soft/RSSHub/data/cookiecloud.env`:

```bash
export COOKIE_CLOUD_HOST=http://127.0.0.1:8088
export COOKIE_CLOUD_UUID=rsshub
export COOKIE_CLOUD_PASSWORD=789000123
export COOKIE_CLOUD_INTERVAL=3600
export COOKIE_CLOUD_DEBUG=true
```

---

## 第五阶段: 配置服务管理

### 5.1 创建 sv 服务脚本

创建 `$PREFIX/var/service/rsshub/run`:

```bash
#!/data/data/com.termux/files/usr/bin/sh
exec 2>&1

HOME_DIR=/data/data/com.termux/files/home
cd $HOME_DIR/soft/RSSHub

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
```

**关键点:**
- 使用 `set -a` 自动导出所有变量
- 等待 CookieCloud API 就绪后再启动

### 5.2 创建日志服务

创建 `$PREFIX/var/service/rsshub/log/run`:

```bash
#!/data/data/com.termux/files/usr/bin/sh
exec svlogd -tt /data/data/com.termux/files/home/soft/RSSHub/data/logs/
```

### 5.3 配置 SVDIR

```bash
# 添加到 ~/.bashrc
export SVDIR=$PREFIX/var/service
```

### 5.4 启动服务

```bash
export SVDIR=$PREFIX/var/service
sv start rsshub
```

---

## 第六阶段: 配置开机自启

### 6.1 创建 Termux:Boot 脚本

创建 `~/.termux/boot/start-rsshub.sh`:

```bash
#!/data/data/com.termux/files/usr/bin/bash
termux-wake-lock
sleep 2

export SVDIR=/data/data/com.termux/files/usr/var/service

# 先启动 CookieCloud
sv start cookiecloud-api
sleep 3

# 再启动 RSSHub
sv start rsshub
```

### 6.2 设置执行权限

```bash
chmod +x ~/.termux/boot/start-rsshub.sh
```

---

## 第七阶段: 验证

### 7.1 检查服务状态

```bash
export SVDIR=$PREFIX/var/service
sv status rsshub
sv status cookiecloud-api
```

**输出:**
```
run: rsshub: (pid 14594) 65s
run: cookiecloud-api: (pid 3968) 99995s
```

### 7.2 测试访问

```bash
# 测试 RSSHub
curl http://127.0.0.1:1200

# 测试 CookieCloud 路由
curl http://127.0.0.1:1200/cookiecloud/test
```

**输出:**
```
<title>Welcome to RSSHub!</title>
<title>CookieCloud 测试</title>
```

### 7.3 查看日志

```bash
tail -f ~/soft/RSSHub/data/logs/current
```

---

## 遇到的问题及解决方案

### 问题 1: WSL 访问 /mnt/c 性能差

**现象:** pnpm install 超时

**解决:** 使用 `/tmp` 目录 (WSL 原生文件系统)

### 问题 2: tar 硬链接权限问题

**现象:** `tar: Cannot hard link: Permission denied`

**解决:** 使用 `--hard-dereference` 选项重新打包

### 问题 3: sv 命令找不到服务目录

**现象:** `fail: unable to change to service directory: file does not exist`

**解决:** 设置 `SVDIR` 环境变量

### 问题 4: CookieCloud 配置未加载

**现象:** `CookieCloud not load`

**解决:** 使用 `set -a` 自动导出环境变量

### 问题 5: 服务启动后立即停止

**现象:** sv status 显示 down

**解决:** 检查 run 脚本权限和语法，确保使用正确的 shebang

---

## 最终配置

### 目录结构

```
~/soft/RSSHub/
├── cookiecloud/        # CookieCloud 插件
├── data/
│   ├── env             # RSSHub 环境变量
│   ├── cookiecloud.env # CookieCloud 配置
│   └── logs/           # 服务日志
├── dist/               # 编译产物
├── node_modules/       # 依赖
└── rsshub              # 启动脚本
```

### 服务配置

| 服务 | 状态 | PID |
|------|------|-----|
| cookiecloud-api | 运行中 | 3968 |
| rsshub | 运行中 | 14594 |

### 访问地址

- RSSHub: http://192.168.35.177:1200
- CookieCloud: http://192.168.35.177:8088

---

## 常用命令参考

```bash
# 服务管理
export SVDIR=$PREFIX/var/service
sv status rsshub
sv restart rsshub
sv restart cookiecloud-api

# 查看日志
tail -f ~/soft/RSSHub/data/logs/current

# 手动启动
cd ~/soft/RSSHub && ./rsshub

# 编辑配置
nano ~/soft/RSSHub/data/env
nano ~/soft/RSSHub/data/cookiecloud.env
```

---

## 时间记录

| 阶段 | 操作 | 耗时 |
|------|------|------|
| 环境准备 | 安装 Node.js 24 | 约 10 秒 |
| 编译 | pnpm install | 约 22 秒 |
| 编译 | npm run build | 约 46 秒 |
| 传输 | tar + scp | 约 15 秒 |
| 安装 | 解压 + 配置 | 约 2 分钟 |
| 服务配置 | sv 脚本 + 启动 | 约 5 分钟 |
| **总计** | | **约 10 分钟** |

---

## 附录: 完整脚本列表

1. `build.sh` - 交叉编译脚本
2. `rsshub.sv.run` - sv 服务脚本
3. `rsshub.sv.log.run` - sv 日志服务脚本
4. `start-rsshub.boot.sh` - 开机启动脚本
5. `env.template` - RSSHub 环境变量模板
6. `cookiecloud.env.template` - CookieCloud 配置模板
7. `README.md` - 使用说明

---

**记录时间:** 2026-08-06
**记录人:** Codex CLI