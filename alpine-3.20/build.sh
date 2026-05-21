#!/usr/bin/env bash
# 构造 talon-alpine-3.20.<patch>-x86_64.tar.gz baseimage tarball。
#
# 流程：
#   1) docker run alpine:3.20 容器
#   2) 容器内 apk update && apk add（从 packages.txt 读包列表）
#   3) 清理 apk cache + man pages + locale，缩小体积
#   4) docker export 把整个容器 fs 抓出来 → tar.gz
#   5) 算 SHA256，输出到同名 .sha256 文件
#
# 用法：
#   bash alpine-3.20/build.sh              # 用默认 version 3.20.0
#   VERSION=3.20.1 bash alpine-3.20/build.sh
#
# 产物：
#   ./out/talon-alpine-3.20.0-x86_64.tar.gz
#   ./out/talon-alpine-3.20.0-x86_64.tar.gz.sha256
#
# GitHub Action 直接复用本脚本——只需提供 VERSION 环境变量。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

VERSION="${VERSION:-0.1.0}"          # 我们自己的语义版本，与 git tag (vX.Y.Z) 对齐
ALPINE_BASE_TAG="${ALPINE_BASE_TAG:-3.20}"   # 底层 alpine major+minor；patch 跟 alpine:3.20 这个滚动 tag
ARCH="x86_64"
NAME="talon-alpine-${VERSION}"
OUT_DIR="$REPO_ROOT/out"
TARBALL="$OUT_DIR/${NAME}-${ARCH}.tar.gz"

mkdir -p "$OUT_DIR"

if [[ -t 1 ]]; then
  G=$'\033[32m'; B=$'\033[1m'; O=$'\033[0m'
else
  G=''; B=''; O=''
fi
say() { printf "${B}==>${O} %s\n" "$*"; }
ok()  { printf "${G}  ✓${O} %s\n" "$*"; }

# ---- 1. 读 packages.txt ----
PKG_LIST=$(grep -vE '^\s*(#|$)' "$SCRIPT_DIR/packages.txt" | tr '\n' ' ' | sed 's/[[:space:]]\+$//')
[[ -n "$PKG_LIST" ]] || { echo "packages.txt 为空" >&2; exit 1; }
say "packages.txt: $(echo "$PKG_LIST" | wc -w | tr -d ' ') 个包"

# ---- 2. docker 镜像可用性 ----
command -v docker >/dev/null 2>&1 || { echo "docker 不在 PATH" >&2; exit 1; }
say "拉取 alpine:${ALPINE_BASE_TAG}"
docker pull --quiet "alpine:${ALPINE_BASE_TAG}" >/dev/null

# ---- 3. 在临时容器里装包 + 清理 ----
# 不用 docker build / Dockerfile：单次脚本 + docker export 输出更直观，
# 不留 image layer，也省得管 image 名。
# 用 `sleep 3600` 当 init 让容器保持 running 状态，docker exec 才能进去；
# 跑完手动 docker stop 进入 stopped，再 export。
CID=$(docker run --platform linux/amd64 -d "alpine:${ALPINE_BASE_TAG}" sleep 3600)
trap 'docker rm -f "$CID" >/dev/null 2>&1 || true' EXIT

say "在容器内装包"
# `apk add` 一次性装所有包；--no-cache 让 apk 用 ramfs index、不写 /var/cache/apk
docker exec "$CID" sh -c "apk update >/dev/null && apk add --no-cache $PKG_LIST" \
  || { echo "apk add 失败" >&2; exit 1; }

say "清理体积冗余"
# - rm -rf /var/cache/apk /tmp /var/log/* /usr/share/man /usr/share/doc：
#   man / doc / log 一律不需要（sandbox 内查文档应当用 --help / online）；
#   apk 的 index 留 /lib/apk 不动（用户还要能 apk info）
# - 删 *.pyc *__pycache__*：第一次 import 时会重新生成，省 ~5MB
# - 删 npm cache：node 装包后留下的 metadata 没人看
docker exec "$CID" sh -c '
  set -e
  rm -rf /var/cache/apk/* /tmp/* /var/log/*
  rm -rf /usr/share/man /usr/share/doc /usr/share/info
  find /usr/lib/python3* -name __pycache__ -type d -exec rm -rf {} + 2>/dev/null || true
  find /usr/lib/python3* -name "*.pyc" -delete 2>/dev/null || true
  rm -rf /root/.npm
' || true   # 清理失败不致命，只是体积大点

# ---- 4. docker export → tarball ----
say "停止 sleep 占位进程，准备 export"
docker stop --time 2 "$CID" >/dev/null
say "导出 rootfs → $TARBALL"
# `docker export` 输出 tar；管到 gzip --best 让发布物最小
docker export "$CID" | gzip --best > "$TARBALL"
ok "rootfs ready"

# ---- 5. SHA256 + 尺寸 ----
SHA=$(shasum -a 256 "$TARBALL" | awk '{print $1}')
SIZE_RAW=$(docker export "$CID" | wc -c | tr -d ' ')
SIZE_TGZ=$(stat -f %z "$TARBALL" 2>/dev/null || stat -c %s "$TARBALL" 2>/dev/null)
echo "$SHA  $(basename "$TARBALL")" > "$TARBALL.sha256"

# ---- 6. 报告 ----
echo
echo "${B}=== build summary ===${O}"
printf "  name:   %s\n" "$NAME"
printf "  arch:   %s\n" "$ARCH"
printf "  packages: %d 个\n" "$(echo "$PKG_LIST" | wc -w | tr -d ' ')"
printf "  rootfs (uncompressed): %s MB\n" "$(awk -v s="$SIZE_RAW" 'BEGIN{printf "%.1f", s/1024/1024}')"
printf "  tarball (gzip --best): %s MB\n" "$(awk -v s="$SIZE_TGZ" 'BEGIN{printf "%.1f", s/1024/1024}')"
printf "  sha256: %s\n" "$SHA"
printf "  path:   %s\n" "$TARBALL"
echo
ok "done"
