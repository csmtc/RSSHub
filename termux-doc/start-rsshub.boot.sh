#!/data/data/com.termux/files/usr/bin/bash
# ============================================================
# Termux:Boot 开机启动脚本
# ============================================================
# 安装位置: ~/.termux/boot/start-rsshub.sh
# 功能: 开机自动启动 CookieCloud 和 RSSHub 服务
#
# 前提条件:
#   1. 安装 Termux:Boot 应用
#   2. 已配置 sv 服务 (cookiecloud-api 和 rsshub)

termux-wake-lock

# 等待 termux-services 初始化
sleep 2

# 设置 SVDIR
export SVDIR=/data/data/com.termux/files/usr/var/service

# 先启动 CookieCloud API
sv start cookiecloud-api

# 等待 CookieCloud 就绪
sleep 3

# 启动 RSSHub (会自动等待 CookieCloud)
sv start rsshub