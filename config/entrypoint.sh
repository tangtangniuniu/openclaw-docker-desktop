#!/bin/bash
set -e

echo "========================================="
echo "  OpenClaw Ubuntu Desktop 启动中..."
echo "========================================="

# ===== 1. 首次初始化 =====
if [ ! -f "/docker_config/init_flag" ]; then
    echo ">>> 首次启动，执行初始化..."
    bash /docker_config/setup_user.sh
    echo "ok" > /docker_config/init_flag
fi

# ===== 2. 检查并执行自定义启动脚本 =====
if [ -f "/home/share/start.sh" ]; then
    echo ">>> 检测到自定义启动脚本 /home/share/start.sh，正在执行..."
    chmod +x /home/share/start.sh
    bash /home/share/start.sh || echo "警告: 自定义启动脚本执行失败，继续启动..."
fi

# ===== 3. 启动系统服务 =====

# 启动 SSH
echo ">>> 启动 SSH..."
/usr/sbin/sshd

# 启动 DBus
echo ">>> 启动 DBus..."
mkdir -p /var/run/dbus
dbus-daemon --system --fork 2>/dev/null || true

# 启动 code-server
echo ">>> 启动 code-server..."
if [ ! -z ${DISABLE_HTTPS+x} ]; then
    su "$USER" -c "code-server --bind-addr=0.0.0.0:5000 &" 2>/dev/null || true
else
    su "$USER" -c "code-server --cert $HTTPS_CERT --cert-key $HTTPS_CERT_KEY --bind-addr=0.0.0.0:5000 &" 2>/dev/null || true
fi

# 启动远程桌面
echo ">>> 启动远程桌面 (${REMOTE_DESKTOP:-nomachine})..."
if [ "${REMOTE_DESKTOP}" = "nomachine" ]; then
    bash /docker_config/start_nomachine.sh &
elif [ "${REMOTE_DESKTOP}" = "kasmvnc" ]; then
    bash /docker_config/start_kasmvnc.sh &
elif [ "${REMOTE_DESKTOP}" = "novnc" ]; then
    bash /docker_config/start_novnc.sh &
else
    echo "不支持的远程桌面类型: $REMOTE_DESKTOP"
fi

# 等待远程桌面启动
sleep 2

# ===== 4. 启动 OpenClaw Gateway =====
echo ">>> 初始化 OpenClaw..."
bash /docker_config/openclaw_init.sh

echo ">>> 启动 OpenClaw Gateway..."

export DBUS_SESSION_BUS_ADDRESS=/dev/null
export BUN_INSTALL="/usr/local"
export PATH="/usr/local/bin:$PATH"

# 定义清理函数
cleanup() {
    echo "=== 接收到停止信号，正在关闭服务 ==="
    if [ -n "$GATEWAY_PID" ]; then
        kill -TERM "$GATEWAY_PID" 2>/dev/null || true
        wait "$GATEWAY_PID" 2>/dev/null || true
    fi
    # 停止远程桌面
    if [ "${REMOTE_DESKTOP}" = "nomachine" ]; then
        /etc/NX/nxserver --shutdown 2>/dev/null || true
    fi
    echo "=== 服务已停止 ==="
    exit 0
}

# 捕获终止信号
trap cleanup SIGTERM SIGINT SIGQUIT

# 以 ubuntu 用户身份启动 OpenClaw Gateway（前台主进程）
if [ -n "$OPENCLAW_GATEWAY_TOKEN" ]; then
    gosu "$USER" env \
        HOME="/home/$USER" \
        DBUS_SESSION_BUS_ADDRESS=/dev/null \
        BUN_INSTALL="/usr/local" \
        PATH="/usr/local/bin:/usr/bin:/bin:$PATH" \
        NODE_PATH="/usr/local/lib/node_modules" \
        openclaw gateway run \
        --bind "${OPENCLAW_GATEWAY_BIND:-0.0.0.0}" \
        --port "${OPENCLAW_GATEWAY_PORT:-18789}" \
        --token "$OPENCLAW_GATEWAY_TOKEN" \
        --verbose &
    GATEWAY_PID=$!
    echo "=== OpenClaw Gateway 已启动 (PID: $GATEWAY_PID) ==="
    wait "$GATEWAY_PID"
    EXIT_CODE=$?
    echo "=== OpenClaw Gateway 已退出 (退出码: $EXIT_CODE) ==="
    exit $EXIT_CODE
else
    echo "未配置 OPENCLAW_GATEWAY_TOKEN，OpenClaw Gateway 未启动"
    echo "容器以桌面模式运行，按 Ctrl+C 退出"
    # 保持容器运行
    tail -f /dev/null &
    TAIL_PID=$!
    wait "$TAIL_PID"
fi
