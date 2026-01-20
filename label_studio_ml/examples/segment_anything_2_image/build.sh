#!/bin/bash

# Build and push Docker image for Label Studio ML Backend SAM2
# Usage:
#   ./build.sh [OPTIONS]
#   DOCKER_USERNAME=yourname DOCKER_IMAGE=your-image ./build.sh
#   ./build.sh --tag latest --push

set -e  # Exit on error

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default values (can be overridden by environment variables or arguments)
DOCKER_USERNAME=${DOCKER_USERNAME:-"neurobot"}
IMAGE_NAME=${IMAGE_NAME:-"label-studio-ml-sam2"}
TAG=${TAG:-"latest"}
BUILD_TARGET=${BUILD_TARGET:-""}  # Empty by default, only use if specified
TEST_ENV=${TEST_ENV:-""}
PUSH=${PUSH:-"false"}
NO_CACHE=${NO_CACHE:-"false"}
DOCKER_PLATFORM=${DOCKER_PLATFORM:-""}
BASE_IMAGE=${BASE_IMAGE:-""}
SAM2_DIR=${SAM2_DIR:-"sam2"}
DOCKER_CONTEXT=${DOCKER_CONTEXT:-"."}
DOCKERFILE_PATH=${DOCKERFILE_PATH:-"Dockerfile"}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --username)
            DOCKER_USERNAME="$2"
            shift 2
            ;;
        --image)
            IMAGE_NAME="$2"
            shift 2
            ;;
        --tag)
            TAG="$2"
            shift 2
            ;;
        --target)
            BUILD_TARGET="$2"
            shift 2
            ;;
        --platform)
            DOCKER_PLATFORM="$2"
            shift 2
            ;;
        --base-image)
            BASE_IMAGE="$2"
            shift 2
            ;;
        --sam2-dir)
            SAM2_DIR="$2"
            shift 2
            ;;
        --context)
            DOCKER_CONTEXT="$2"
            shift 2
            ;;
        --dockerfile)
            DOCKERFILE_PATH="$2"
            shift 2
            ;;
        --test-env)
            TEST_ENV="true"
            shift
            ;;
        --push)
            PUSH="true"
            shift
            ;;
        --no-cache)
            NO_CACHE="true"
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --username USERNAME    Docker Hub username (default: \$DOCKER_USERNAME or 'your-dockerhub-username')"
            echo "  --image IMAGE_NAME     Image name (default: \$IMAGE_NAME or 'label-studio-ml-sam2')"
            echo "  --tag TAG              Image tag (default: \$TAG or 'latest')"
            echo "  --target TARGET        Docker build target (default: \$BUILD_TARGET or 'production')"
            echo "  --platform PLATFORM    Docker build platform (e.g. linux/amd64, linux/arm64)"
            echo "  --base-image IMAGE     Base image (e.g. nvcr.io/nvidia/pytorch:24.10-py3)"
            echo "  --sam2-dir PATH        Path to sam2 within build context (default: sam2)"
            echo "  --context PATH         Docker build context (default: .)"
            echo "  --dockerfile PATH      Dockerfile path (default: Dockerfile)"
            echo "  --test-env             Include test dependencies"
            echo "  --push                 Push image to Docker Hub after building"
            echo "  --no-cache             Build without using cache"
            echo "  --help, -h             Show this help message"
            echo ""
            echo "Environment variables:"
            echo "  DOCKER_USERNAME        Docker Hub username"
            echo "  DOCKER_PASSWORD        Docker Hub password (for CI/CD)"
            echo "  IMAGE_NAME             Image name"
            echo "  TAG                    Image tag"
            echo "  BUILD_TARGET           Docker build target"
            echo "  DOCKER_PLATFORM        Docker build platform (e.g. linux/amd64, linux/arm64)"
            echo "  BASE_IMAGE             Base image (e.g. nvcr.io/nvidia/pytorch:24.10-py3)"
            echo "  SAM2_DIR               Path to sam2 within build context"
            echo "  DOCKER_CONTEXT         Docker build context"
            echo "  DOCKERFILE_PATH        Dockerfile path"
            echo "  TEST_ENV               Set to 'true' to include test dependencies"
            echo "  PUSH                   Set to 'true' to push after building"
            echo ""
            echo "Examples:"
            echo "  $0 --username myuser --tag v1.0.0 --push"
            echo "  DOCKER_USERNAME=myuser TAG=v1.0.0 PUSH=true $0"
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Full image name
FULL_IMAGE_NAME="${DOCKER_USERNAME}/${IMAGE_NAME}:${TAG}"

# Pick a better default base image on ARM (DGX Spark / Grace-class)
if [ -z "${BASE_IMAGE}" ]; then
    ARCH="$(uname -m)"
    if [ "${ARCH}" = "aarch64" ] || [ "${ARCH}" = "arm64" ]; then
        BASE_IMAGE="nvcr.io/nvidia/pytorch:24.10-py3"
        echo -e "${YELLOW}Detected ARM host; defaulting BASE_IMAGE=${BASE_IMAGE}.${NC}"
        echo -e "${YELLOW}If NGC requires auth, run: docker login nvcr.io${NC}"
    else
        BASE_IMAGE="pytorch/pytorch:2.5.1-cuda12.4-cudnn9-runtime"
    fi
fi

# If running on ARM and no platform was provided, default to amd64
if [ -z "${DOCKER_PLATFORM}" ]; then
    ARCH="$(uname -m)"
    if [ "${ARCH}" = "aarch64" ] || [ "${ARCH}" = "arm64" ]; then
        DOCKER_PLATFORM="linux/amd64"
        echo -e "${YELLOW}Detected ARM host; defaulting to ${DOCKER_PLATFORM} for base image compatibility.${NC}"
        echo -e "${YELLOW}If you have binfmt/qemu disabled, enable it or pass --platform explicitly.${NC}"
    fi
fi

if [ "${DOCKER_PLATFORM}" = "linux/arm64" ]; then
    echo -e "${YELLOW}Warning: the base image pytorch/pytorch:2.5.1-cuda12.4-cudnn9-runtime is amd64-only.${NC}"
    echo -e "${YELLOW}Use --platform linux/amd64 on ARM, or switch to an arm64-compatible base image (CPU-only).${NC}"
fi

# Print configuration
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Docker Image Build Configuration${NC}"
echo -e "${GREEN}========================================${NC}"
echo "Docker Username: ${DOCKER_USERNAME}"
echo "Image Name:      ${IMAGE_NAME}"
echo "Tag:             ${TAG}"
echo "Full Image:      ${FULL_IMAGE_NAME}"
echo "Build Target:    ${BUILD_TARGET:-'none (single stage)'}"
echo "Platform:        ${DOCKER_PLATFORM:-'default'}"
echo "Base Image:      ${BASE_IMAGE}"
echo "SAM2 Dir:        ${SAM2_DIR}"
echo "Build Context:   ${DOCKER_CONTEXT}"
echo "Dockerfile:      ${DOCKERFILE_PATH}"
echo "Test Env:        ${TEST_ENV:-'false'}"
echo "Push Image:      ${PUSH}"
echo "No Cache:        ${NO_CACHE}"
echo -e "${GREEN}========================================${NC}"
echo ""

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
    echo -e "${RED}Error: Docker is not running or not accessible${NC}"
    exit 1
fi

# Build arguments
BUILD_ARGS=(
    --build-arg "TEST_ENV=${TEST_ENV}"
    --build-arg "BASE_IMAGE=${BASE_IMAGE}"
    --build-arg "SAM2_DIR=${SAM2_DIR}"
)

# Only add --target if BUILD_TARGET is specified and not empty
if [ -n "${BUILD_TARGET}" ] && [ "${BUILD_TARGET}" != "" ]; then
    BUILD_ARGS+=(--target "${BUILD_TARGET}")
fi

if [ "${NO_CACHE}" = "true" ]; then
    BUILD_ARGS+=(--no-cache)
fi

if [ -n "${DOCKER_PLATFORM}" ]; then
    BUILD_ARGS+=(--platform "${DOCKER_PLATFORM}")
fi

# Build the image
echo -e "${YELLOW}Building Docker image: ${FULL_IMAGE_NAME}${NC}"
echo ""

if docker build "${BUILD_ARGS[@]}" -f "${DOCKERFILE_PATH}" -t "${FULL_IMAGE_NAME}" "${DOCKER_CONTEXT}"; then
    echo ""
    echo -e "${GREEN}✓ Image built successfully: ${FULL_IMAGE_NAME}${NC}"
else
    echo ""
    echo -e "${RED}✗ Image build failed${NC}"
    exit 1
fi

# Optionally tag as latest
if [ "${TAG}" != "latest" ]; then
    LATEST_TAG="${DOCKER_USERNAME}/${IMAGE_NAME}:latest"
    echo -e "${YELLOW}Tagging as latest: ${LATEST_TAG}${NC}"
    docker tag "${FULL_IMAGE_NAME}" "${LATEST_TAG}"
    echo -e "${GREEN}✓ Tagged as latest${NC}"
fi

# Push to Docker Hub if requested
if [ "${PUSH}" = "true" ]; then
    echo ""
    echo -e "${YELLOW}Pushing image to Docker Hub...${NC}"
    
    # Check if already logged in
    if ! docker info | grep -q "Username"; then
        if [ -z "${DOCKER_PASSWORD}" ]; then
            echo -e "${YELLOW}Docker Hub login required${NC}"
            echo "Please login to Docker Hub:"
            docker login
        else
            echo "Logging in to Docker Hub..."
            echo "${DOCKER_PASSWORD}" | docker login -u "${DOCKER_USERNAME}" --password-stdin
        fi
    fi
    
    # Push the image
    if docker push "${FULL_IMAGE_NAME}"; then
        echo -e "${GREEN}✓ Image pushed successfully: ${FULL_IMAGE_NAME}${NC}"
        
        # Push latest tag if created
        if [ "${TAG}" != "latest" ]; then
            if docker push "${LATEST_TAG}"; then
                echo -e "${GREEN}✓ Latest tag pushed successfully: ${LATEST_TAG}${NC}"
            else
                echo -e "${YELLOW}Warning: Failed to push latest tag${NC}"
            fi
        fi
    else
        echo -e "${RED}✗ Failed to push image${NC}"
        exit 1
    fi
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Build completed successfully!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Image: ${FULL_IMAGE_NAME}"
if [ "${PUSH}" = "true" ]; then
    echo "Pushed to: https://hub.docker.com/r/${DOCKER_USERNAME}/${IMAGE_NAME}"
fi
echo ""
echo "To use this image, update docker-compose.yml:"
echo "  image: ${FULL_IMAGE_NAME}"
