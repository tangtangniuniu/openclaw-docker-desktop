# OpenClaw Ubuntu Desktop

基于 Ubuntu 24.04 的 Docker 镜像，集成 XFCE 桌面环境、中文支持和 OpenClaw AI Gateway。

## 特性

- Ubuntu 24.04 + XFCE4 桌面环境
- 完整中文支持（locale、字体、fcitx 拼音输入法）
- OpenClaw v2026.3.2 + 中文 IM 插件（钉钉、NapCat、QQ Bot、企业微信）
- 多种远程桌面方式（NoMachine / KasmVNC / noVNC）
- SSH + code-server 远程开发
- Chromium + Playwright 浏览器自动化

## 快速开始

```bash
# 1. 构建镜像
./build.sh

# 2. 配置环境变量
cp .env.example .env
vim .env  # 修改 API_KEY、BASE_URL、OPENCLAW_GATEWAY_TOKEN 等

# 3. 启动容器
./run.sh
```

## 构建

```bash
# 默认构建
./build.sh

# 自定义标签
./build.sh --tag myimage:v1
```

## 运行

```bash
# 普通模式
./run.sh

# 特权模式（某些远程桌面功能可能需要）
./run.sh --privileged

# 指定数据目录
./run.sh --data-dir /path/to/data

# 查看所有选项
./run.sh --help
```

### 参数说明

| 参数 | 说明 | 默认值 |
|------|------|--------|
| `--privileged` | 特权模式运行 | 否 |
| `--env-file <file>` | 环境变量文件 | `.env` |
| `--image <name>` | 镜像名称 | `openclaw-ubuntu-desktop:latest` |
| `--name <name>` | 容器名称 | `openclaw-desktop` |
| `--data-dir <dir>` | 数据目录 | `./data` |

## 端口说明

| 端口 | 服务 | 说明 |
|------|------|------|
| 22 | SSH | `ssh ubuntu@<host>` |
| 4000 | 远程桌面 | KasmVNC / noVNC Web 访问 |
| 5000 | code-server | Web IDE |
| 18789 | OpenClaw Gateway | AI Gateway API |
| 18790 | OpenClaw Bridge | Bridge 服务 |

## 远程桌面

默认使用 NoMachine，可通过 `.env` 中的 `REMOTE_DESKTOP` 切换：

### NoMachine（默认）

1. 下载 [NoMachine 客户端](https://www.nomachine.com/download)
2. 新建连接：协议 NX，地址为容器所在主机 IP
3. 用户名 `ubuntu`，密码见 `.env` 中 `PASSWORD`

### KasmVNC

设置 `REMOTE_DESKTOP=kasmvnc`，浏览器打开 `https://<host>:4000`

### noVNC

设置 `REMOTE_DESKTOP=novnc`，浏览器打开 `https://<host>:4000`

## 数据持久化

| 容器路径 | 说明 |
|----------|------|
| `/home/share/` | 数据根目录，映射到宿主机 |
| `/home/share/ubuntu/` | ubuntu 用户主目录 |
| `/home/share/ubuntu/.openclaw/` | OpenClaw 配置和插件 |
| `/home/share/ubuntu/.openclaw/workspace/` | OpenClaw 工作空间 |

## 自定义启动脚本

在数据目录中创建 `start.sh`，容器每次启动时会自动执行：

```bash
# data/start.sh
#!/bin/bash
echo "自定义初始化..."
# 安装额外软件、启动自定义服务等
```

## 环境变量

详见 `.env.example`，主要配置项：

### 桌面配置

| 变量 | 说明 | 默认值 |
|------|------|--------|
| `PASSWORD` | 用户密码 | `ubuntu` |
| `REMOTE_DESKTOP` | 远程桌面类型 | `nomachine` |
| `VNC_THREADS` | VNC 线程数 | `2` |

### OpenClaw 配置

| 变量 | 说明 | 默认值 |
|------|------|--------|
| `MODEL_ID` | 模型 ID | `gpt-4o` |
| `BASE_URL` | API 地址 | - |
| `API_KEY` | API 密钥 | - |
| `API_PROTOCOL` | API 协议 | `openai-completions` |
| `OPENCLAW_GATEWAY_TOKEN` | Gateway 认证令牌 | - |
| `OPENCLAW_GATEWAY_PORT` | Gateway 端口 | `18789` |

### IM 渠道

| 变量前缀 | 渠道 |
|----------|------|
| `TELEGRAM_` | Telegram |
| `FEISHU_` | 飞书 |
| `DINGTALK_` | 钉钉 |
| `QQBOT_` | QQ 机器人 |
| `NAPCAT_` | NapCat (OneBot v11) |
| `WECOM_` | 企业微信 |

## 常见问题

### NoMachine 连接失败

尝试使用特权模式启动：

```bash
./run.sh --privileged
```

### 中文输入法不工作

远程桌面登录后，在终端执行：

```bash
fcitx &
```

或通过系统托盘启动 fcitx。

### 容器内无法访问网络

检查 Docker 网络配置，确认宿主机 DNS 可用：

```bash
docker exec openclaw-desktop ping -c 1 8.8.8.8
```

### 修改端口映射

编辑 `run.sh` 或在命令行传入额外参数：

```bash
./run.sh -p 2222:22 -p 8080:18789
```
