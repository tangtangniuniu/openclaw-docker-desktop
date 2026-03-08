#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
IMAGE="openclaw-ubuntu-desktop:latest"
CONTAINER_NAME="openclaw-desktop"
PRIVILEGED=""
ENV_FILE=""
DATA_DIR=""
EXTRA_ARGS=""

# 加载 .env 文件中的 DATA_DIR（如果存在）
if [ -f "$SCRIPT_DIR/.env" ]; then
    DATA_DIR_FROM_ENV=$(grep -E '^DATA_DIR=' "$SCRIPT_DIR/.env" 2>/dev/null | cut -d'=' -f2-)
    if [ -n "$DATA_DIR_FROM_ENV" ]; then
        DATA_DIR="$DATA_DIR_FROM_ENV"
    fi
fi

# 解析参数
while [[ $# -gt 0 ]]; do
    case "$1" in
        --privileged)
            PRIVILEGED="--privileged"
            shift
            ;;
        --env-file)
            ENV_FILE="$2"
            shift 2
            ;;
        --image|-i)
            IMAGE="$2"
            shift 2
            ;;
        --name|-n)
            CONTAINER_NAME="$2"
            shift 2
            ;;
        --data-dir|-d)
            DATA_DIR="$2"
            shift 2
            ;;
        --help|-h)
            echo "用法: $0 [选项]"
            echo ""
            echo "选项:"
            echo "  --privileged          使用特权模式运行容器"
            echo "  --env-file <file>     指定环境变量文件 (默认: .env)"
            echo "  --image, -i <image>   指定镜像名称 (默认: $IMAGE)"
            echo "  --name, -n <name>     指定容器名称 (默认: $CONTAINER_NAME)"
            echo "  --data-dir, -d <dir>  指定数据目录 (默认: ./data)"
            echo "  --help, -h            显示帮助信息"
            exit 0
            ;;
        *)
            EXTRA_ARGS="$EXTRA_ARGS $1"
            shift
            ;;
    esac
done

# 默认值
DATA_DIR="${DATA_DIR:-$SCRIPT_DIR/data}"
ENV_FILE="${ENV_FILE:-$SCRIPT_DIR/.env}"

# 创建数据目录
mkdir -p "$DATA_DIR"

# 构建 env-file 参数
ENV_FILE_ARG=""
if [ -f "$ENV_FILE" ]; then
    ENV_FILE_ARG="--env-file $ENV_FILE"
    echo "加载环境变量: $ENV_FILE"
else
    echo "警告: 未找到 .env 文件 ($ENV_FILE)"
    echo "建议: cp .env.example .env && vim .env"
fi

# 停止并移除同名容器（如果存在）
if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    echo "停止并移除已有容器: $CONTAINER_NAME"
    docker stop "$CONTAINER_NAME" 2>/dev/null || true
    docker rm "$CONTAINER_NAME" 2>/dev/null || true
fi

echo "========================================="
echo "  启动 OpenClaw Ubuntu Desktop"
echo "  镜像: $IMAGE"
echo "  容器: $CONTAINER_NAME"
echo "  数据: $DATA_DIR"
if [ -n "$PRIVILEGED" ]; then
    echo "  模式: 特权模式"
fi
echo "========================================="

docker run -d \
    --name "$CONTAINER_NAME" \
    --restart unless-stopped \
    --shm-size=2g \
    $PRIVILEGED \
    $ENV_FILE_ARG \
    -v "$DATA_DIR:/home/share" \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -p 22:22 \
    -p 4000:4000 \
    -p 5000:5000 \
    -p 18789:18789 \
    -p 18790:18790 \
    $EXTRA_ARGS \
    "$IMAGE"

echo ""
echo "========================================="
echo "  容器已启动: $CONTAINER_NAME"
echo "========================================="
echo ""
echo "连接方式:"
echo "  SSH:            ssh ubuntu@localhost"
echo "  远程桌面:       NoMachine 连接 localhost"
echo "  code-server:    https://localhost:5000"
echo "  OpenClaw UI:    http://localhost:18789"
echo ""
echo "默认密码: ubuntu (可通过 .env 中 PASSWORD 修改)"
echo ""
echo "管理命令:"
echo "  查看日志:  docker logs -f $CONTAINER_NAME"
echo "  进入容器:  docker exec -it $CONTAINER_NAME bash"
echo "  停止容器:  docker stop $CONTAINER_NAME"
echo "  删除容器:  docker rm $CONTAINER_NAME"
