# Docker 镜像构建和推送指南

本文档说明如何使用 `build.sh` 脚本构建和推送 Docker 镜像到 Docker Hub。

## 快速开始

### 1. 基本构建（不推送）

```bash
./build.sh --username your-dockerhub-username --image label-studio-ml-sam2 --tag latest
```

### 2. 构建并推送

```bash
./build.sh --username your-dockerhub-username --image label-studio-ml-sam2 --tag v1.0.0 --push
```

### 3. 使用环境变量

```bash
export DOCKER_USERNAME=your-dockerhub-username
export IMAGE_NAME=label-studio-ml-sam2
export TAG=v1.0.0
export PUSH=true

./build.sh
```

## 参数说明

### 命令行参数

- `--username USERNAME`: Docker Hub 用户名
- `--image IMAGE_NAME`: 镜像名称（默认: `label-studio-ml-sam2`）
- `--tag TAG`: 镜像标签（默认: `latest`）
- `--target TARGET`: Docker 构建目标（默认: `production`）
- `--test-env`: 包含测试依赖
- `--push`: 构建后推送到 Docker Hub
- `--no-cache`: 不使用缓存构建
- `--help, -h`: 显示帮助信息

### 环境变量

所有参数都可以通过环境变量设置：

- `DOCKER_USERNAME`: Docker Hub 用户名
- `DOCKER_PASSWORD`: Docker Hub 密码（用于 CI/CD，避免交互式登录）
- `IMAGE_NAME`: 镜像名称
- `TAG`: 镜像标签
- `BUILD_TARGET`: Docker 构建目标
- `TEST_ENV`: 设置为 `true` 以包含测试依赖
- `PUSH`: 设置为 `true` 以在构建后推送

## 使用示例

### 本地开发构建

```bash
# 构建生产镜像
./build.sh --username myuser --tag dev

# 构建包含测试依赖的镜像
./build.sh --username myuser --tag dev-test --test-env
```

### 生产环境构建

```bash
# 构建并推送版本标签
./build.sh \
  --username myuser \
  --image label-studio-ml-sam2 \
  --tag v1.0.0 \
  --push

# 同时会创建 latest 标签
```

### CI/CD 使用

在 CI/CD 环境中，使用环境变量和 Docker Hub token：

```bash
export DOCKER_USERNAME=myuser
export DOCKER_PASSWORD=${DOCKERHUB_TOKEN}  # 从 CI secrets 获取
export IMAGE_NAME=label-studio-ml-sam2
export TAG=${CI_COMMIT_TAG:-${CI_COMMIT_SHA:0:8}}
export PUSH=true

./build.sh
```

## 更新 docker-compose.yml

构建完成后，更新 `docker-compose.yml` 使用你的镜像：

```yaml
services:
  ml-backend:
    image: your-dockerhub-username/label-studio-ml-sam2:latest
    # 移除 build 部分，直接使用镜像
    # build:
    #   ...
```

## CI/CD 集成

### GitHub Actions

已在 `.github/workflows/build-and-push.yml` 中配置了 GitHub Actions 工作流。

**设置 Secrets:**
1. 进入 GitHub 仓库 Settings → Secrets and variables → Actions
2. 添加以下 secrets:
   - `DOCKER_USERNAME`: Docker Hub 用户名
   - `DOCKER_PASSWORD`: Docker Hub 访问令牌（不是密码）

**触发方式:**
- 推送到 `main`/`master` 分支 → 构建并推送 `latest` 标签
- 创建 git tag (如 `v1.0.0`) → 构建并推送对应标签
- 手动触发 (workflow_dispatch) → 可指定自定义标签

### GitLab CI

创建 `.gitlab-ci.yml`:

```yaml
build:
  stage: build
  script:
    - cd label_studio_ml/examples/segment_anything_2_image
    - chmod +x build.sh
    - |
      DOCKER_USERNAME=$CI_REGISTRY_USER
      DOCKER_PASSWORD=$CI_REGISTRY_PASSWORD
      IMAGE_NAME=label-studio-ml-sam2
      TAG=$CI_COMMIT_TAG
      PUSH=true
      ./build.sh --push
  only:
    - tags
```

## 故障排除

### Docker 登录问题

如果遇到登录问题：

```bash
# 手动登录
docker login

# 或使用 token（推荐用于 CI/CD）
echo $DOCKER_PASSWORD | docker login -u $DOCKER_USERNAME --password-stdin
```

### 权限问题

确保脚本有执行权限：

```bash
chmod +x build.sh
```

### 构建失败

1. 检查 Docker 是否运行: `docker info`
2. 检查网络连接（下载依赖需要）
3. 使用 `--no-cache` 重新构建: `./build.sh --no-cache`

## 最佳实践

1. **版本标签**: 使用语义化版本（如 `v1.0.0`）而不是 `latest`
2. **多标签**: 脚本会自动创建 `latest` 标签（如果指定了其他标签）
3. **CI/CD**: 使用 Docker Hub 访问令牌而不是密码
4. **缓存**: 在 CI 中考虑使用 Docker layer caching
5. **测试**: 在推送前本地测试镜像
