# RSSHub for Termux

在 Android Termux 上运行 RSSHub，集成 CookieCloud 自动同步 Cookie。

## 快速开始

### 方式一: 使用预编译包 (推荐)

```bash
# 1. 下载预编译包
wget https://example.com/rsshub-termux.tar.gz

# 2. 解压并安装
tar xzf rsshub-termux.tar.gz
cd rsshub-termux
./install.sh

# 3. 配置
cd ~/soft/RSSHub
cp data/env.template data/env
cp data/cookiecloud.env.template data/cookiecloud.env
nano data/cookiecloud.env

# 4. 启动
./rsshub
```

### 方式二: 从源码编译

```bash
# 1. 克隆仓库
git clone https://github.com/DIYgod/RSSHub.git
cd RSSHub

# 2. 运行编译脚本
chmod +x termux-doc/build.sh
./termux-doc/build.sh

# 3. 安装
tar xzf output/rsshub-termux.tar.gz
cd rsshub-termux
./install.sh
```

## 目录结构

```
~/soft/RSSHub/
├── cookiecloud/            # CookieCloud 插件
│   ├── index.js            # 入口文件
│   ├── libs/               # 核心库
│   └── libs/cookies/       # Cookie 定义文件
├── data/
│   ├── env                 # RSSHub 环境变量
│   ├── cookiecloud.env     # CookieCloud 配置
│   └── logs/               # 服务日志
├── dist/                   # 编译产物
├── node_modules/           # 依赖
└── rsshub                  # 启动脚本
```

## 配置说明

### RSSHub 配置 (`data/env`)

```bash
export NODE_ENV=production
export NODE_OPTIONS=--max-http-header-size=32768
export PORT=1200
export LISTEN_INADDR_ANY=true
```

### CookieCloud 配置 (`data/cookiecloud.env`)

```bash
export COOKIE_CLOUD_HOST=http://127.0.0.1:8088
export COOKIE_CLOUD_UUID=your-uuid
export COOKIE_CLOUD_PASSWORD=your-password
export COOKIE_CLOUD_INTERVAL=3600
export COOKIE_CLOUD_DEBUG=true
```

## 服务管理

### 手动启动

```bash
cd ~/soft/RSSHub
./rsshub
```

### 使用 sv 服务管理

```bash
# 安装 sv 服务
cp termux-doc/rsshub.sv.run $PREFIX/var/service/rsshub/run
chmod +x $PREFIX/var/service/rsshub/run

# 设置 SVDIR (添加到 ~/.bashrc)
export SVDIR=$PREFIX/var/service

# 管理服务
sv start rsshub
sv stop rsshub
sv restart rsshub
sv status rsshub
```

### 开机自启 (Termux:Boot)

```bash
# 安装 Termux:Boot 应用后执行
mkdir -p ~/.termux/boot
cp termux-doc/start-rsshub.boot.sh ~/.termux/boot/
chmod +x ~/.termux/boot/start-rsshub.boot.sh
```

## CookieCloud 使用

### 支持的网站

| 网站 | 环境变量 | Cookie 域名 |
|------|---------|-------------|
| Bilibili | `BILIBILI_COOKIE_{uid}` | bilibili.com |
| 小红书 | `XIAOHONGSHU_COOKIE` | xiaohongshu.com |
| 微博 | `WEIBO_COOKIE` | weibo.cn |
| 知乎 | `ZHIHU_COOKIES` | zhihu.com |
| JavDB | `JAVDB_SESSION` | javdb.com |
| 其他 | `COOKIECLOUD_ALL` | 所有域名 |

### 添加自定义网站

在 `cookiecloud/libs/cookies/` 目录下创建 JS 文件:

```javascript
export default {
    "ENV_VARIABLE_NAME": [
        {
            "domain": "example.com",
            "name": "cookie_name"  // 可选，留空获取所有 Cookie
        }
    ]
}
```

### 验证配置

```bash
# 测试 CookieCloud 路由
curl http://localhost:1200/cookiecloud/test

# 强制同步并查看结果
curl http://localhost:1200/cookiecloud/BILIBILI_COOKIE?remote
```

## 访问地址

- 本地: http://localhost:1200
- 局域网: http://<设备IP>:1200
- CookieCloud 调试: http://<设备IP>:1200/cookiecloud/:keys

## 故障排除

### CookieCloud 未加载

检查环境变量是否正确导出:

```bash
cd ~/soft/RSSHub
source data/env
source data/cookiecloud.env
echo $COOKIE_CLOUD_HOST  # 应该输出服务器地址
```

### 服务无法启动

查看日志:

```bash
tail -f ~/soft/RSSHub/data/logs/current
```

### 端口被占用

```bash
lsof -i :1200
```

## 相关链接

- [RSSHub 文档](https://docs.rsshub.app)
- [CookieCloud 项目](https://github.com/easychen/CookieCloud)
- [Termux 官网](https://termux.dev)

## 许可证

MIT License