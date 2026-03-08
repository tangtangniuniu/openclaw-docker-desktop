FROM ubuntu:24.04

LABEL maintainer="openclaw-ubuntu-desktop"

# ===== 环境变量 =====
ENV DEBIAN_FRONTEND=noninteractive \
    USER=ubuntu \
    PASSWORD=ubuntu \
    UID=1000 \
    GID=1000 \
    LANG=zh_CN.UTF-8 \
    LANGUAGE=zh_CN:zh \
    LC_ALL=zh_CN.UTF-8 \
    HTTPS_CERT=/etc/ssl/certs/ssl-cert-snakeoil.pem \
    HTTPS_CERT_KEY=/etc/ssl/private/ssl-cert-snakeoil.key \
    VGL_DISPLAY=egl \
    REMOTE_DESKTOP=nomachine \
    VNC_THREADS=2 \
    BUN_INSTALL="/usr/local" \
    NODE_PATH=/usr/local/lib/node_modules \
    TERM=xterm-256color

ENV PATH="/usr/local/bin:/usr/NX/scripts/vgl:$PATH"

# ===== 基础层：中文 locale + 时区 + 字体 =====
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        locales tzdata language-pack-zh-hans \
        fonts-wqy-zenhei fonts-noto-cjk fonts-noto-color-emoji && \
    locale-gen zh_CN.UTF-8 && \
    echo "LANG=zh_CN.UTF-8" > /etc/default/locale && \
    echo "LANGUAGE=zh_CN:zh" >> /etc/default/locale && \
    echo "LC_ALL=zh_CN.UTF-8" >> /etc/default/locale && \
    update-locale LANG=zh_CN.UTF-8 LC_ALL=zh_CN.UTF-8 && \
    echo "Asia/Shanghai" > /etc/timezone && \
    ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime && \
    dpkg-reconfigure -f noninteractive tzdata && \
    rm -rf /var/lib/apt/lists/*

# ===== 输入法层：fcitx + googlepinyin =====
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        fcitx fcitx-googlepinyin fcitx-frontend-gtk3 fcitx-ui-classic \
        dbus-x11 im-config && \
    im-config -n fcitx && \
    rm -rf /var/lib/apt/lists/*

ENV GTK_IM_MODULE=fcitx \
    QT_IM_MODULE=fcitx \
    XMODIFIERS=@im=fcitx \
    INPUT_METHOD=fcitx

# ===== 桌面层：xfce4 + 应用 =====
# Remove default ubuntu user if exists
RUN userdel -r ubuntu 2>/dev/null || true

RUN apt-get update && \
    add-apt-repository -y ppa:mozillateam/ppa && \
    mkdir -p /etc/apt/preferences.d && \
    printf "Package: firefox*\nPin: release o=LP-PPA-mozillateam\nPin-Priority: 1001\n" \
        > /etc/apt/preferences.d/mozilla-firefox && \
    apt-get install -y --no-install-recommends \
        xfce4 terminator pulseaudio ffmpeg firefox dbus-x11 bzip2 && \
    apt-get remove -y xfce4-screensaver --purge || true && \
    update-alternatives --set x-www-browser /usr/bin/firefox && \
    rm -rf /var/lib/apt/lists/*

ENV DBUS_SYSTEM_BUS_ADDRESS=unix:path=/host/run/dbus/system_bus_socket

# ===== 工具层：基础系统工具 =====
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        sudo vim gedit locales gnupg2 wget curl zip unzip \
        lsb-release bash-completion ca-certificates \
        net-tools iputils-ping mesa-utils \
        software-properties-common build-essential \
        python3 python3-pip python3-numpy \
        openssh-server openssl git git-lfs tmux \
        jq gosu socat tini && \
    rm -rf /var/lib/apt/lists/*

# ===== 远程桌面层 =====
COPY config/pre_install.sh /docker_config/pre_install.sh
COPY config/post_install.sh /docker_config/post_install.sh
COPY config/install_nomachine.sh /docker_config/install_nomachine.sh
COPY config/install_kasmvnc.sh /docker_config/install_kasmvnc.sh
COPY config/install_novnc.sh /docker_config/install_novnc.sh
COPY config/start_nomachine.sh /docker_config/start_nomachine.sh
COPY config/start_kasmvnc.sh /docker_config/start_kasmvnc.sh
COPY config/start_novnc.sh /docker_config/start_novnc.sh

RUN chmod +x /docker_config/*.sh && \
    bash /docker_config/post_install.sh && \
    rm -rf /var/lib/apt/lists/*

# ===== Node.js 层 =====
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - && \
    apt-get install -y nodejs && \
    npm install -g npm@latest && \
    npm install -g \
        openclaw@2026.3.2 \
        opencode-ai@latest \
        playwright \
        playwright-extra \
        puppeteer-extra-plugin-stealth && \
    curl -fsSL https://bun.sh/install | BUN_INSTALL=/usr/local bash && \
    /usr/local/bin/bun install -g @tobilu/qmd && \
    rm -rf /var/lib/apt/lists/* /tmp/* /root/.npm /root/.cache

# ===== Chromium 层 =====
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        chromium-browser fonts-liberation && \
    npx playwright install chromium --with-deps && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /root/.cache

# ===== 插件安装层 =====
# 预装到 /opt/openclaw-extensions，首次启动时复制到用户目录
RUN mkdir -p /opt/openclaw-extensions /opt/openclaw-qqbot && \
    cd /opt/openclaw-extensions && \
    git clone --depth 1 https://github.com/soimy/openclaw-channel-dingtalk.git dingtalk && \
    cd dingtalk && npm install --omit=dev --legacy-peer-deps && \
    cd /opt/openclaw-extensions && \
    git clone --depth 1 -b v4.17.25 https://github.com/Daiyimo/openclaw-napcat.git napcat && \
    cd napcat && npm install --production && \
    cd /opt && \
    git clone --depth 1 https://github.com/justlovemaki/qqbot.git openclaw-qqbot && \
    cd openclaw-qqbot && npm install --omit=dev --legacy-peer-deps || true && \
    cd /opt/openclaw-extensions && \
    mkdir -p wecom && cd wecom && \
    npm init -y && npm install @sunnoy/wecom@v1.5.1 && \
    find /opt/openclaw-extensions -name ".git" -type d -exec rm -rf {} + 2>/dev/null || true && \
    rm -rf /opt/openclaw-qqbot/.git && \
    rm -rf /tmp/* /root/.npm /root/.cache

# ===== 最终配置层 =====
COPY config/setup_user.sh /docker_config/setup_user.sh
COPY config/openclaw_init.sh /docker_config/openclaw_init.sh
COPY config/entrypoint.sh /docker_config/entrypoint.sh

RUN chmod +x /docker_config/setup_user.sh \
              /docker_config/openclaw_init.sh \
              /docker_config/entrypoint.sh

# SSH 配置
RUN mkdir -p /var/run/sshd && \
    sed -i 's/#*PermitRootLogin prohibit-password/PermitRootLogin yes/g' /etc/ssh/sshd_config && \
    sed -i 's@session\s*required\s*pam_loginuid.so@session optional pam_loginuid.so@g' /etc/pam.d/sshd

VOLUME /home/share

EXPOSE 22 4000 5000 18789 18790

ENTRYPOINT ["/docker_config/entrypoint.sh"]
