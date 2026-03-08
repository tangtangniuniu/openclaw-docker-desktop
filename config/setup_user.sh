#!/bin/bash
set -e

echo "=== 用户初始化 ==="

USER=${USER:-ubuntu}
PASSWORD=${PASSWORD:-ubuntu}
UID_VAL=${UID:-1000}
GID_VAL=${GID:-1000}

# 创建持久化目录
mkdir -p /home/share/ubuntu

# 创建用户组和用户
groupadd -g "$GID_VAL" "$USER" 2>/dev/null || true
useradd --no-create-home --no-log-init -u "$UID_VAL" -g "$GID_VAL" -d "/home/$USER" -s /bin/bash "$USER" 2>/dev/null || true

# 建立主目录软链接
if [ ! -L "/home/$USER" ]; then
    rm -rf "/home/$USER"
    ln -sf /home/share/ubuntu "/home/$USER"
fi

# 确保主目录存在基础结构
mkdir -p "/home/share/ubuntu/.config"
mkdir -p "/home/share/ubuntu/.local/share"

# 配置 sudo 权限（免密）
usermod -aG sudo "$USER"
echo "$USER ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/$USER"
chmod 440 "/etc/sudoers.d/$USER"

# 设置密码
echo "root:$PASSWORD" | chpasswd
echo "$USER:$PASSWORD" | chpasswd

# 设置 ssl-cert 组
usermod -aG ssl-cert "$USER" 2>/dev/null || true

# 配置 Docker socket 访问（DooD）
if [ -S /var/run/docker.sock ]; then
    DOCKER_GID=$(stat -c '%g' /var/run/docker.sock)
    groupadd -g "$DOCKER_GID" docker 2>/dev/null || true
    usermod -aG docker "$USER"
    echo "Docker socket 已挂载，用户 $USER 已加入 docker 组 (GID=$DOCKER_GID)"
fi

# 创建 /run/user 目录
mkdir -p "/run/user/$UID_VAL"
chown "$UID_VAL:$GID_VAL" "/run/user/$UID_VAL"

# 设置主目录权限
chown -R "$UID_VAL:$GID_VAL" /home/share/ubuntu

# 配置 python 别名
update-alternatives --install /usr/bin/python python /usr/bin/python3 2 2>/dev/null || true

# 写入环境变量到 /etc/environment
env | grep -Ev "CMD=|PWD=|SHLVL=|_=|DEBIAN_FRONTEND=|USER=|HOME=|UID=|GID=|PASSWORD=" > /etc/environment

# 配置 fcitx 输入法自启动
mkdir -p "/home/share/ubuntu/.config/autostart"
cat > "/home/share/ubuntu/.config/autostart/fcitx.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Fcitx
Exec=fcitx-autostart
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
EOF
chown -R "$UID_VAL:$GID_VAL" "/home/share/ubuntu/.config"

echo "=== 用户初始化完成 ==="
