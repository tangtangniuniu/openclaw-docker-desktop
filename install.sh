#!/bin/bash
###############################################################################
# install.sh — 在 Ubuntu 24.04 裸机/服务器上一键安装 OpenClaw Desktop 全套环境
#
# 特性：
#   - 断点续装：每步完成后记录进度，重新运行自动跳过已完成步骤
#   - 强制重装某步：FORCE_STEP=4 sudo bash install.sh
#   - 从头开始：RESET=1 sudo bash install.sh
#
# 用法：sudo bash install.sh
###############################################################################
set -euo pipefail

# ===== 颜色输出 =====
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }
log_step()  { echo -e "\n${CYAN}========== $* ==========${NC}"; }

# ===== 权限检查 =====
if [ "$(id -u)" -ne 0 ]; then
    log_error "请使用 root 权限运行: sudo bash $0"
    exit 1
fi

# ===== 可配置变量 =====
TARGET_USER="${TARGET_USER:-ubuntu}"
TARGET_UID="${TARGET_UID:-1000}"
TARGET_GID="${TARGET_GID:-1000}"
TARGET_PASSWORD="${TARGET_PASSWORD:-ubuntu}"

NODE_VERSION="${NODE_VERSION:-22.14.0}"
BUN_VERSION="${BUN_VERSION:-1.2.5}"
CODE_SERVER_VERSION="${CODE_SERVER_VERSION:-4.108.2}"
NOVNC_VERSION="${NOVNC_VERSION:-1.6.0}"
KASMVNC_VERSION="${KASMVNC_VERSION:-1.4.0}"
PLAYWRIGHT_VERSION="${PLAYWRIGHT_VERSION:-1.58.0}"
OPENCLAW_VERSION="${OPENCLAW_VERSION:-2026.3.2}"

PLAYWRIGHT_BROWSERS_PATH="${PLAYWRIGHT_BROWSERS_PATH:-/opt/pw-browsers}"
INSTALL_DIR="${INSTALL_DIR:-/opt/openclaw-desktop}"
CONFIG_DIR="${INSTALL_DIR}/config"

GHPROXY="${GHPROXY:-https://ghfast.top}"
APT_MIRROR="${APT_MIRROR:-mirrors.aliyun.com}"

export DEBIAN_FRONTEND=noninteractive

# ===== 进度跟踪 =====
PROGRESS_FILE="/var/lib/openclaw-install-progress"

if [ "${RESET:-}" = "1" ]; then
    rm -f "$PROGRESS_FILE"
    log_info "已重置安装进度"
fi

# 如果指定了 FORCE_STEP，删除该步骤的完成标记
if [ -n "${FORCE_STEP:-}" ]; then
    sed -i "/^${FORCE_STEP}$/d" "$PROGRESS_FILE" 2>/dev/null || true
    log_info "将重新执行步骤 $FORCE_STEP"
fi

touch "$PROGRESS_FILE"

step_done() {
    grep -qx "$1" "$PROGRESS_FILE" 2>/dev/null
}

mark_done() {
    echo "$1" >> "$PROGRESS_FILE"
    log_info "步骤 $1 完成 ✓"
}

# ===== 架构检测 =====
ARCH=$(dpkg --print-architecture)
CODENAME=$(lsb_release --short --codename 2>/dev/null || echo "noble")
log_info "系统架构: $ARCH, 版本代号: $CODENAME"

TOTAL_STEPS=14

###############################################################################
# 1. APT 镜像加速 + 基础证书
###############################################################################
if step_done 1; then
    log_info "[1/${TOTAL_STEPS}] APT 镜像 — 已完成，跳过"
else
    log_step "1/${TOTAL_STEPS} 配置 APT 镜像 (${APT_MIRROR})"

    cp /etc/apt/sources.list.d/ubuntu.sources /etc/apt/sources.list.d/ubuntu.sources.bak 2>/dev/null || true

    sed -i "s|http://archive.ubuntu.com|http://${APT_MIRROR}|g" /etc/apt/sources.list.d/ubuntu.sources
    sed -i "s|http://security.ubuntu.com|http://${APT_MIRROR}|g" /etc/apt/sources.list.d/ubuntu.sources
    sed -i "s|https\?://mirrors.aliyun.com|http://${APT_MIRROR}|g" /etc/apt/sources.list.d/ubuntu.sources

    apt-get update
    apt-get install -y --no-install-recommends ca-certificates

    sed -i "s|http://${APT_MIRROR}|https://${APT_MIRROR}|g" /etc/apt/sources.list.d/ubuntu.sources
    apt-get update

    mark_done 1
fi

###############################################################################
# 2. 中文 Locale + 时区 + 字体
###############################################################################
if step_done 2; then
    log_info "[2/${TOTAL_STEPS}] 中文环境 — 已完成，跳过"
else
    log_step "2/${TOTAL_STEPS} 配置中文环境与时区"

    apt-get install -y --no-install-recommends \
        locales tzdata language-pack-zh-hans \
        fonts-wqy-zenhei fonts-noto-cjk fonts-noto-color-emoji fonts-liberation

    locale-gen zh_CN.UTF-8
    cat > /etc/default/locale <<EOF
LANG=zh_CN.UTF-8
LANGUAGE=zh_CN:zh
LC_ALL=zh_CN.UTF-8
EOF
    update-locale LANG=zh_CN.UTF-8 LC_ALL=zh_CN.UTF-8

    echo "Asia/Shanghai" > /etc/timezone
    ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
    dpkg-reconfigure -f noninteractive tzdata

    mark_done 2
fi

###############################################################################
# 3. 输入法: fcitx5
###############################################################################
if step_done 3; then
    log_info "[3/${TOTAL_STEPS}] fcitx5 输入法 — 已完成，跳过"
else
    log_step "3/${TOTAL_STEPS} 安装 fcitx5 中文输入法"

    apt-get install -y --no-install-recommends \
        fcitx5 fcitx5-chinese-addons fcitx5-frontend-gtk3 fcitx5-frontend-qt5 \
        fcitx5-config-qt \
        dbus-x11 im-config

    im-config -n fcitx5

    grep -q "GTK_IM_MODULE=fcitx" /etc/environment 2>/dev/null || cat >> /etc/environment <<'EOF'
GTK_IM_MODULE=fcitx
QT_IM_MODULE=fcitx
XMODIFIERS=@im=fcitx
INPUT_METHOD=fcitx
EOF

    mark_done 3
fi

###############################################################################
# 4. 系统基础工具
###############################################################################
if step_done 4; then
    log_info "[4/${TOTAL_STEPS}] 系统基础工具 — 已完成，跳过"
else
    log_step "4/${TOTAL_STEPS} 安装系统基础工具"

    apt-get install -y --no-install-recommends \
        sudo vim gedit gnupg2 wget curl zip unzip \
        lsb-release bash-completion \
        net-tools iputils-ping mesa-utils \
        software-properties-common build-essential \
        python3-pip=3.12.3-1ubuntu0.11 python3-numpy=3.12.3-1ubuntu0.11 \
		python3.12-venv=3.12.3-1ubuntu0.11 python3.12=3.12.3-1ubuntu0.11
        openssh-server openssl git git-lfs tmux \
        jq gosu socat tini \
        x11-utils xvfb bzip2 \
        libnss3 libgbm1 libasound2t64

    mkdir -p /etc/pip
    cat > /etc/pip/pip.conf <<EOF
[global]
index-url = https://mirrors.aliyun.com/pypi/simple/
trusted-host = mirrors.aliyun.com
EOF

    update-alternatives --install /usr/bin/python python /usr/bin/python3 2 2>/dev/null || true

    mark_done 4
fi

###############################################################################
# 5. uv + Docker CLI
###############################################################################
if step_done 5; then
    log_info "[5/${TOTAL_STEPS}] uv + Docker CLI — 已完成，跳过"
else
    log_step "5/${TOTAL_STEPS} 安装 uv + Docker CLI"

    # uv
    curl -LsSf https://astral.sh/uv/install.sh | sh
    if [ -f /root/.local/bin/uv ]; then
        ln -sf /root/.local/bin/uv /usr/local/bin/uv
        ln -sf /root/.local/bin/uvx /usr/local/bin/uvx 2>/dev/null || true
    fi

    # Docker CLI
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://mirrors.aliyun.com/docker-ce/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc
    echo "deb [arch=${ARCH} signed-by=/etc/apt/keyrings/docker.asc] https://mirrors.aliyun.com/docker-ce/linux/ubuntu ${CODENAME} stable" \
        > /etc/apt/sources.list.d/docker.list
    apt-get update
    apt-get install -y --no-install-recommends docker-ce-cli docker-compose-plugin

    mark_done 5
fi

###############################################################################
# 6. XFCE4 桌面环境
###############################################################################
if step_done 6; then
    log_info "[6/${TOTAL_STEPS}] XFCE4 桌面 — 已完成，跳过"
else
    log_step "6/${TOTAL_STEPS} 安装 XFCE4 桌面环境"

    apt-get install -y --no-install-recommends \
        xfce4 xfce4-terminal terminator pulseaudio ffmpeg

    apt-get remove -y xfce4-screensaver --purge 2>/dev/null || true

    mark_done 6
fi

###############################################################################
# 7. 远程桌面: TurboVNC + NoVNC + KasmVNC + NoMachine
###############################################################################
if step_done 7; then
    log_info "[7/${TOTAL_STEPS}] 远程桌面 — 已完成，跳过"
else
    log_step "7/${TOTAL_STEPS} 安装远程桌面"

    # TurboVNC
    log_info "安装 TurboVNC..."
    wget -q -O- https://packagecloud.io/dcommander/turbovnc/gpgkey | gpg --dearmor > /etc/apt/trusted.gpg.d/TurboVNC.gpg
    wget -O /etc/apt/sources.list.d/TurboVNC.list "${GHPROXY}/https://raw.githubusercontent.com/TurboVNC/repo/main/TurboVNC.list"
    apt-get update
    apt-get install -y turbovnc
    rm -f /etc/apt/sources.list.d/TurboVNC.list
    echo "xset s off && /usr/bin/startxfce4" > /opt/TurboVNC/bin/xstartup.turbovnc

    # NoVNC
    log_info "安装 NoVNC v${NOVNC_VERSION}..."
    curl -fsSL "${GHPROXY}/https://github.com/novnc/noVNC/archive/v${NOVNC_VERSION}.tar.gz" | tar -xzf - -C /opt
    mv -f "/opt/noVNC-${NOVNC_VERSION}" /opt/noVNC
    ln -snf /opt/noVNC/vnc.html /opt/noVNC/index.html
    git clone "${GHPROXY}/https://github.com/novnc/websockify.git" /opt/noVNC/utils/websockify

    # KasmVNC
    log_info "安装 KasmVNC v${KASMVNC_VERSION}..."
    curl -fSL "${GHPROXY}/https://github.com/kasmtech/KasmVNC/releases/download/v${KASMVNC_VERSION}/kasmvncserver_${CODENAME}_${KASMVNC_VERSION}_${ARCH}.deb" \
        -o /tmp/kasmvncserver.deb || true
    if [ -f /tmp/kasmvncserver.deb ]; then
        apt-get install -y /tmp/kasmvncserver.deb || log_warn "KasmVNC 安装失败，可忽略"
        rm -f /tmp/kasmvncserver.deb
    fi
    if [ -f /usr/lib/kasmvncserver/select-de.sh ]; then
        sed -i 's/exec xfce4-session/xset s off;&/' /usr/lib/kasmvncserver/select-de.sh
    fi

    # NoMachine
    log_info "安装 NoMachine..."
    if [ "$ARCH" = "amd64" ]; then
        curl -fSL "https://www.nomachine.com/free/linux/64/deb" -o /tmp/nomachine.deb
    elif [ "$ARCH" = "arm64" ]; then
        curl -fSL "https://www.nomachine.com/free/arm/64/deb" -o /tmp/nomachine.deb
    else
        log_warn "NoMachine 不支持架构: $ARCH，跳过"
    fi
    if [ -f /tmp/nomachine.deb ]; then
        dpkg -i /tmp/nomachine.deb || apt-get install -f -y
        rm -f /tmp/nomachine.deb
        groupmod -g 2000 nx 2>/dev/null || true
        sed -i "s|#EnableClipboard both|EnableClipboard both |g" /usr/NX/etc/server.cfg 2>/dev/null || true
        sed -i '/DefaultDesktopCommand/c\DefaultDesktopCommand "xset s off && /usr/bin/startxfce4"' /usr/NX/etc/node.cfg 2>/dev/null || true
    fi

    mark_done 7
fi

###############################################################################
# 8. code-server
###############################################################################
if step_done 8; then
    log_info "[8/${TOTAL_STEPS}] code-server — 已完成，跳过"
else
    log_step "8/${TOTAL_STEPS} 安装 code-server v${CODE_SERVER_VERSION}"

    curl -fSL "${GHPROXY}/https://github.com/coder/code-server/releases/download/v${CODE_SERVER_VERSION}/code-server_${CODE_SERVER_VERSION}_${ARCH}.deb" \
        -o /tmp/code-server.deb
    dpkg -i /tmp/code-server.deb || apt-get install -f -y
    rm -f /tmp/code-server.deb

    mark_done 8
fi

###############################################################################
# 9. Node.js + npm 全局包
###############################################################################
if step_done 9; then
    log_info "[9/${TOTAL_STEPS}] Node.js + npm — 已完成，跳过"
else
    log_step "9/${TOTAL_STEPS} 安装 Node.js v${NODE_VERSION} + 全局 npm 包"

    curl -fsSL "https://npmmirror.com/mirrors/node/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-x64.tar.xz" | \
        tar -xJ -C /usr/local --strip-components=1

    npm config set registry https://registry.npmmirror.com
    npm config set fetch-retries 5
    npm config set fetch-retry-mintimeout 20000
    npm config set fetch-retry-maxtimeout 120000

    git config --global url."https://github.com/".insteadOf "ssh://git@github.com/"

    npm install -g npm@latest
    npm install -g \
        "openclaw@${OPENCLAW_VERSION}" \
        opencode-ai@latest \
        "playwright@${PLAYWRIGHT_VERSION}" \
        playwright-extra \
        puppeteer-extra-plugin-stealth

    mark_done 9
fi

###############################################################################
# 10. nvm + pnpm
###############################################################################
if step_done 10; then
    log_info "[10/${TOTAL_STEPS}] nvm + pnpm — 已完成，跳过"
else
    log_step "10/${TOTAL_STEPS} 安装 nvm + pnpm"

    export NVM_DIR="/usr/local/nvm"
    mkdir -p "$NVM_DIR"
    curl -o- "${GHPROXY}/https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh" | \
        NVM_DIR="$NVM_DIR" bash

    npm install -g pnpm

    mark_done 10
fi

###############################################################################
# 11. Playwright 浏览器 + Bun + qmd
###############################################################################
if step_done 11; then
    log_info "[11/${TOTAL_STEPS}] Playwright + Bun + qmd — 已完成，跳过"
else
    log_step "11/${TOTAL_STEPS} 安装 Playwright 浏览器 + Bun v${BUN_VERSION} + qmd"

    mkdir -p "$PLAYWRIGHT_BROWSERS_PATH"
    export PLAYWRIGHT_BROWSERS_PATH
    npx playwright install chromium --with-deps

    CHROME_BIN=$(find "$PLAYWRIGHT_BROWSERS_PATH" -name "chrome" -type f | head -n 1)
    if [ -n "$CHROME_BIN" ]; then
        ln -sf "$CHROME_BIN" /usr/bin/google-chrome
        ln -sf "$CHROME_BIN" /usr/bin/chromium-browser
        ln -sf "$CHROME_BIN" /usr/bin/x-www-browser
    fi

    curl -fsSL "${GHPROXY}/https://github.com/oven-sh/bun/releases/download/bun-v${BUN_VERSION}/bun-linux-x64.zip" \
        -o /tmp/bun.zip
    unzip -o /tmp/bun.zip -d /tmp
    mv /tmp/bun-linux-x64/bun /usr/local/bin/bun
    chmod +x /usr/local/bin/bun
    rm -rf /tmp/bun*

    /usr/local/bin/bun install -g @tobilu/qmd

    mark_done 11
fi

###############################################################################
# 12. OpenClaw 插件预装
###############################################################################
if step_done 12; then
    log_info "[12/${TOTAL_STEPS}] OpenClaw 插件 — 已完成，跳过"
else
    log_step "12/${TOTAL_STEPS} 预装 OpenClaw 插件"

    mkdir -p /opt/openclaw-extensions /opt/openclaw-qqbot

    if [ ! -d /opt/openclaw-extensions/dingtalk ]; then
        log_info "安装 dingtalk 插件..."
        cd /opt/openclaw-extensions
        git clone --depth 1 "${GHPROXY}/https://github.com/soimy/openclaw-channel-dingtalk.git" dingtalk
        cd dingtalk && npm install --omit=dev --legacy-peer-deps
    fi

    if [ ! -d /opt/openclaw-extensions/napcat ]; then
        log_info "安装 napcat 插件..."
        cd /opt/openclaw-extensions
        git clone --depth 1 -b v4.17.25 "${GHPROXY}/https://github.com/Daiyimo/openclaw-napcat.git" napcat
        cd napcat && npm install --production
    fi

    if [ ! -d /opt/openclaw-qqbot/node_modules ]; then
        log_info "安装 qqbot 插件..."
        cd /opt
        rm -rf openclaw-qqbot
        git clone --depth 1 "${GHPROXY}/https://github.com/justlovemaki/qqbot.git" openclaw-qqbot
        cd openclaw-qqbot && (npm install --omit=dev --legacy-peer-deps || true)
    fi

    if [ ! -d /opt/openclaw-extensions/wecom/node_modules ]; then
        log_info "安装 wecom 插件..."
        cd /opt/openclaw-extensions
        mkdir -p wecom && cd wecom
        npm init -y && npm install @sunnoy/wecom@v1.5.1
    fi

    find /opt/openclaw-extensions -name ".git" -type d -exec rm -rf {} + 2>/dev/null || true
    rm -rf /opt/openclaw-qqbot/.git

    mark_done 12
fi

###############################################################################
# 13. 创建用户 + 配置权限
###############################################################################
if step_done 13; then
    log_info "[13/${TOTAL_STEPS}] 用户配置 — 已完成，跳过"
else
    log_step "13/${TOTAL_STEPS} 配置用户 ${TARGET_USER}"

    # 创建用户（如不存在）
    if ! id "$TARGET_USER" &>/dev/null; then
        userdel -r "$TARGET_USER" 2>/dev/null || true
        groupadd -g "$TARGET_GID" "$TARGET_USER" 2>/dev/null || true
        useradd -m -s /bin/bash -u "$TARGET_UID" -g "$TARGET_GID" "$TARGET_USER" 2>/dev/null || true
    fi

    usermod -aG sudo "$TARGET_USER"
    echo "$TARGET_USER ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/$TARGET_USER"
    chmod 440 "/etc/sudoers.d/$TARGET_USER"

    echo "root:${TARGET_PASSWORD}" | chpasswd
    echo "${TARGET_USER}:${TARGET_PASSWORD}" | chpasswd

    usermod -aG ssl-cert "$TARGET_USER" 2>/dev/null || true

    if [ -S /var/run/docker.sock ]; then
        DOCKER_GID=$(stat -c '%g' /var/run/docker.sock)
        groupadd -g "$DOCKER_GID" docker 2>/dev/null || true
        usermod -aG docker "$TARGET_USER"
    fi

    mkdir -p "/run/user/$TARGET_UID"
    chown "$TARGET_UID:$TARGET_GID" "/run/user/$TARGET_UID"

    chown -R "$TARGET_UID:$TARGET_GID" "$PLAYWRIGHT_BROWSERS_PATH" 2>/dev/null || true

    USER_HOME="/home/$TARGET_USER"
    mkdir -p "$USER_HOME/.config/autostart"
    cat > "$USER_HOME/.config/autostart/fcitx5.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Fcitx5
Exec=fcitx5
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
EOF

    # 写入 .bashrc（幂等：先清除旧标记块再写入）
    sed -i '/# >>> openclaw-desktop >>>/,/# <<< openclaw-desktop <<</d' "$USER_HOME/.bashrc" 2>/dev/null || true
    cat >> "$USER_HOME/.bashrc" <<EOF
# >>> openclaw-desktop >>>
alias chromium-browser='chromium-browser --no-sandbox'
alias chrome='google-chrome --no-sandbox'
export NVM_DIR="/usr/local/nvm"
[ -s "\$NVM_DIR/nvm.sh" ] && . "\$NVM_DIR/nvm.sh"
[ -s "\$NVM_DIR/bash_completion" ] && . "\$NVM_DIR/bash_completion"
export LANG=zh_CN.UTF-8
export LC_ALL=zh_CN.UTF-8
export PLAYWRIGHT_BROWSERS_PATH=${PLAYWRIGHT_BROWSERS_PATH}
export NODE_PATH=/usr/local/lib/node_modules
export BUN_INSTALL="/usr/local"
export TERM=xterm-256color
export PATH="/usr/local/bin:\$PATH"
# <<< openclaw-desktop <<<
EOF

    chown -R "$TARGET_UID:$TARGET_GID" "$USER_HOME"

    mark_done 13
fi

###############################################################################
# 14. SSH + 启动/停止脚本 + systemd
###############################################################################
if step_done 14; then
    log_info "[14/${TOTAL_STEPS}] SSH + 启动脚本 — 已完成，跳过"
else
    log_step "14/${TOTAL_STEPS} 配置 SSH + 生成启动/停止脚本"

    mkdir -p /var/run/sshd
    sed -i 's/#*PermitRootLogin prohibit-password/PermitRootLogin yes/g' /etc/ssh/sshd_config
    sed -i 's@session\s*required\s*pam_loginuid.so@session optional pam_loginuid.so@g' /etc/pam.d/sshd

    mkdir -p "$INSTALL_DIR" "$CONFIG_DIR"

    # --- 启动脚本 ---
    cat > "$INSTALL_DIR/start.sh" <<'STARTEOF'
#!/bin/bash
set -e
echo "========================================="
echo "  OpenClaw Ubuntu Desktop 启动中..."
echo "========================================="

export USER="${USER:-ubuntu}"
export PASSWORD="${PASSWORD:-ubuntu}"
export REMOTE_DESKTOP="${REMOTE_DESKTOP:-novnc}"
export VNC_THREADS="${VNC_THREADS:-2}"
export DISABLE_HTTPS="${DISABLE_HTTPS:-true}"
export HTTPS_CERT="${HTTPS_CERT:-/etc/ssl/certs/ssl-cert-snakeoil.pem}"
export HTTPS_CERT_KEY="${HTTPS_CERT_KEY:-/etc/ssl/private/ssl-cert-snakeoil.key}"

echo ">>> 启动 SSH..."
/usr/sbin/sshd 2>/dev/null || true

echo ">>> 启动 DBus..."
mkdir -p /var/run/dbus
dbus-daemon --system --fork 2>/dev/null || true

echo ">>> 启动 code-server..."
if [ -n "${DISABLE_HTTPS}" ]; then
    su "$USER" -c "code-server --bind-addr=0.0.0.0:5000 &" 2>/dev/null || true
else
    su "$USER" -c "code-server --cert $HTTPS_CERT --cert-key $HTTPS_CERT_KEY --bind-addr=0.0.0.0:5000 &" 2>/dev/null || true
fi

echo ">>> 启动远程桌面 (${REMOTE_DESKTOP})..."
if [ "${REMOTE_DESKTOP}" = "nomachine" ]; then
    /etc/NX/nxserver --startup &
elif [ "${REMOTE_DESKTOP}" = "kasmvnc" ]; then
    if [ ! -f "/home/$USER/.vnc/passwd" ]; then
        su "$USER" -c "echo -e \"$PASSWORD\n$PASSWORD\n\" | kasmvncpasswd -u $USER -o -w -r"
    fi
    rm -rf /tmp/.X1000-lock /tmp/.X11-unix/X1000
    if [ -n "${DISABLE_HTTPS}" ]; then
        su "$USER" -c "kasmvncserver :1000 -select-de xfce -interface 0.0.0.0 -websocketPort 4000 -sslOnly 0 -RectThreads $VNC_THREADS" &
    else
        su "$USER" -c "kasmvncserver :1000 -select-de xfce -interface 0.0.0.0 -websocketPort 4000 -cert $HTTPS_CERT -key $HTTPS_CERT_KEY -RectThreads $VNC_THREADS" &
    fi
    su "$USER" -c "pulseaudio --start" 2>/dev/null || true
elif [ "${REMOTE_DESKTOP}" = "novnc" ]; then
    if [ ! -f "/home/$USER/.vnc/passwd" ]; then
        su "$USER" -c "echo -e \"$PASSWORD\n$PASSWORD\ny\n\" | /opt/TurboVNC/bin/vncpasswd"
    fi
    rm -rf /tmp/.X1000-lock /tmp/.X11-unix/X1000
    su "$USER" -c "/opt/TurboVNC/bin/vncserver :1000 -rfbport 5900"
    if [ -n "${DISABLE_HTTPS}" ]; then
        su "$USER" -c "/opt/noVNC/utils/novnc_proxy --vnc localhost:5900 --listen 4000 --heartbeat 10 &"
    else
        su "$USER" -c "/opt/noVNC/utils/novnc_proxy --vnc localhost:5900 --ssl-only --cert $HTTPS_CERT --key $HTTPS_CERT_KEY --listen 4000 --heartbeat 10 &"
    fi
fi

sleep 2

if [ -n "${OPENCLAW_GATEWAY_TOKEN:-}" ]; then
    echo ">>> 启动 OpenClaw Gateway..."
    export DBUS_SESSION_BUS_ADDRESS=/dev/null
    export BUN_INSTALL="/usr/local"
    export PATH="/usr/local/bin:/usr/bin:/bin:$PATH"
    export NODE_PATH="/usr/local/lib/node_modules"
    su "$USER" -c "openclaw gateway run \
        --bind '${OPENCLAW_GATEWAY_BIND:-0.0.0.0}' \
        --port '${OPENCLAW_GATEWAY_PORT:-18789}' \
        --token '$OPENCLAW_GATEWAY_TOKEN' \
        --verbose" &
    echo "OpenClaw Gateway 已启动 (PID: $!)"
fi

echo "========================================="
echo "  OpenClaw Ubuntu Desktop 已启动"
echo "========================================="
echo "  NoVNC:       http://$(hostname -I | awk '{print $1}'):4000"
echo "  code-server: http://$(hostname -I | awk '{print $1}'):5000"
echo "  SSH:         ssh $USER@$(hostname -I | awk '{print $1}')"
echo "========================================="
STARTEOF
    chmod +x "$INSTALL_DIR/start.sh"

    # --- 停止脚本 ---
    cat > "$INSTALL_DIR/stop.sh" <<'STOPEOF'
#!/bin/bash
echo ">>> 停止 OpenClaw Desktop 服务..."
pkill -f "openclaw gateway" 2>/dev/null || true
pkill -f "code-server" 2>/dev/null || true
su "${USER:-ubuntu}" -c "/opt/TurboVNC/bin/vncserver -kill :1000" 2>/dev/null || true
pkill -f "novnc_proxy" 2>/dev/null || true
pkill -f "kasmvncserver" 2>/dev/null || true
/etc/NX/nxserver --shutdown 2>/dev/null || true
echo ">>> 所有服务已停止"
STOPEOF
    chmod +x "$INSTALL_DIR/stop.sh"

    # --- systemd ---
    cat > /etc/systemd/system/openclaw-desktop.service <<EOF
[Unit]
Description=OpenClaw Ubuntu Desktop
After=network.target

[Service]
Type=forking
ExecStart=${INSTALL_DIR}/start.sh
ExecStop=${INSTALL_DIR}/stop.sh
RemainAfterExit=yes
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload

    mark_done 14
fi

###############################################################################
# 清理 + 完成
###############################################################################
apt-get clean
rm -rf /tmp/* /root/.npm /root/.cache

echo ""
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}  OpenClaw Ubuntu Desktop 安装完成！${NC}"
echo -e "${GREEN}============================================${NC}"
echo ""
echo "已安装组件:"
echo "  - 中文环境:    zh_CN.UTF-8 + fcitx5 拼音"
echo "  - 桌面环境:    XFCE4"
echo "  - 远程桌面:    TurboVNC + NoVNC / KasmVNC / NoMachine"
echo "  - Web IDE:     code-server v${CODE_SERVER_VERSION}"
echo "  - Node.js:     v${NODE_VERSION}"
echo "  - nvm + pnpm"
echo "  - Bun:         v${BUN_VERSION}"
echo "  - Python:      $(python3 --version 2>/dev/null)"
echo "  - uv:          $(uv --version 2>/dev/null || echo '已安装')"
echo "  - Playwright:  v${PLAYWRIGHT_VERSION} + Chromium"
echo "  - OpenClaw:    v${OPENCLAW_VERSION}"
echo "  - Docker CLI:  已安装 (DooD 模式)"
echo "  - 插件:        dingtalk, napcat, qqbot, wecom"
echo ""
echo "用户: ${TARGET_USER} (密码: ${TARGET_PASSWORD})"
echo ""
echo "启动: sudo ${INSTALL_DIR}/start.sh"
echo "停止: sudo ${INSTALL_DIR}/stop.sh"
echo "systemd: sudo systemctl enable --now openclaw-desktop"
echo ""
echo "进度文件: ${PROGRESS_FILE}"
echo "重装某步: FORCE_STEP=4 sudo bash $0"
echo "全部重装: RESET=1 sudo bash $0"
echo ""
