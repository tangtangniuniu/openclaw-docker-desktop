# OpenClaw Ubuntu Desktop (GitHub Action 版本)

这个目录包含一个专门为在 GitHub Actions 上自动构建和推送到 Docker Hub 而优化的版本。

## 与本地构建版本的区别

*   **官方源:** 这个版本移除了所有的国内镜像加速（例如阿里云镜像、npm 淘宝镜像、Playwright 镜像和 FastGit 等）。它完全依赖官方渠道，这保证了在 GitHub Actions 的美国服务器上的构建速度和稳定性。
*   **独立的 Dockerfile:** 使用了 `Dockerfile.github` 进行构建，从而不影响你可能针对本地环境调整过的 `Dockerfile`。
*   **自动化流水线:** 包含了 `.github/workflows/docker-publish.yml`，这是一个完整的 CI/CD 工作流，当你将代码推送到 `main` 分支或者创建新 `Tag` 时，它会自动为你构建并发布镜像。

## 如何使用此构建流程

### 1. 配置 GitHub 仓库的 Secrets

在你的 GitHub 仓库中，进入 **Settings** -> **Secrets and variables** -> **Actions**，然后点击 **New repository secret** 添加以下两个密钥：

*   **`DOCKERHUB_USERNAME`**: 你的 Docker Hub 用户名。
*   **`DOCKERHUB_TOKEN`**: 你的 Docker Hub 个人访问令牌（Access Token）。建议在 Docker Hub 的 Account Settings -> Security 中生成一个 Token，而不是直接使用密码，这样更安全。

### 2. 修改镜像名称 (可选)

在 `.github/workflows/docker-publish.yml` 中，默认使用的镜像名称是 `${{ github.repository }}` (例如：`your-username/your-repo-name`)。如果你想推送到其他的仓库名下，你需要修改 `IMAGE_NAME` 环境变量：

```yaml
env:
  REGISTRY: docker.io
  # 将这里修改为你的 Docker Hub 镜像名称，例如：
  IMAGE_NAME: my-username/openclaw-ubuntu-desktop
```

### 3. 触发构建

工作流配置了以下触发条件：
*   **Push 到 main 分支**: 每次将代码合并或推送到 `main` 或 `master` 分支时，会自动构建并打上 `latest` 标签，推送到 Docker Hub。
*   **推送 Tag**: 如果你创建了类似于 `v1.0.0` 的 Tag 并推送到 GitHub，工作流会构建并发布一个带有 `1.0.0` 标签的版本。
*   **手动触发**: 你可以在 GitHub 仓库的 **Actions** 页面选择 `Build and Push Docker Image` 工作流并手动点击 **Run workflow** 运行。

### 4. 拉取你构建的镜像

一旦镜像在 Docker Hub 构建完成并推送，你（或其他用户）就可以使用以下命令拉取它：

```bash
docker pull username/openclaw-ubuntu-desktop:latest
```

*(将 `username/openclaw-ubuntu-desktop` 替换为你在 Docker Hub 的实际路径)*

## 常见问题

**Q: 为什么在本地不用这个 `Dockerfile.github`？**
A: 如果你的网络环境连接国外官方源比较慢，那么这个文件在本地构建可能会耗费大量时间。它是专为 GitHub 位于海外的高速构建服务器设计的。如果在本地，建议继续使用配置了镜像源的原版 `Dockerfile`。
