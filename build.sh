#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEFAULT_TAG="openclaw-ubuntu-desktop:latest"
TAG="$DEFAULT_TAG"

# 解析参数
while [[ $# -gt 0 ]]; do
    case "$1" in
        --tag|-t)
            TAG="$2"
            shift 2
            ;;
        --help|-h)
            echo "用法: $0 [选项]"
            echo ""
            echo "选项:"
            echo "  --tag, -t <name:tag>  指定镜像标签 (默认: $DEFAULT_TAG)"
            echo "  --help, -h            显示帮助信息"
            exit 0
            ;;
        *)
            echo "未知参数: $1"
            echo "使用 --help 查看帮助"
            exit 1
            ;;
    esac
done

BUILD_ARGS=""

echo "========================================="
echo "  构建 OpenClaw Ubuntu Desktop 镜像"
echo "  标签: $TAG"
echo "========================================="

docker build $BUILD_ARGS -t "$TAG" "$SCRIPT_DIR"

echo ""
echo "========================================="
echo "  构建完成: $TAG"
echo "========================================="
echo ""
echo "使用以下命令启动容器:"
echo "  ./run.sh"
echo ""
echo "或使用特权模式:"
echo "  ./run.sh --privileged"
