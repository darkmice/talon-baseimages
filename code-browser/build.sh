#!/usr/bin/env bash
# 构造 talon-code-browser-<version>-x86_64.tar.gz baseimage tarball。
#
# 流程：
#   1) docker build code-browser/Dockerfile → 临时 image
#   2) docker create + docker export 把 rootfs 抓成裸 tar
#   3) gzip --best 输出到 ../out/，与 alpine-3.20/build.sh 同目录
#   4) 算 SHA256
#
# 用法：
#   bash code-browser/build.sh              # 用默认 version 0.1.0
#   VERSION=0.2.0 bash code-browser/build.sh
#
# 产物（在 repo 根的 out/，与 alpine-3.20 共用）：
#   ./out/talon-code-browser-0.1.0-x86_64.tar.gz
#   ./out/talon-code-browser-0.1.0-x86_64.tar.gz.sha256
#
# GitHub Action 直接复用本脚本——只需提供 VERSION 环境变量。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

VERSION="${VERSION:-0.1.0}"
ARCH="x86_64"
NAME="talon-code-browser-${VERSION}"
TAG="talon-baseimages/code-browser:${VERSION}"
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

# ---- 1. docker 可用性 ----
command -v docker >/dev/null 2>&1 || { echo "docker 不在 PATH" >&2; exit 1; }

# ---- 2. docker build ----
# 强制 linux/amd64 平台 —— GH Actions ubuntu-latest 是 amd64，但本地 mac arm 上
# 跑这个脚本时不指定 platform 会拉成 arm64 image，导出后塞进 worker 跑不起来。
say "docker build ${TAG}"
docker build \
  --platform linux/amd64 \
  --file "$SCRIPT_DIR/Dockerfile" \
  --tag "$TAG" \
  "$SCRIPT_DIR"

# ---- 3. docker create + export ----
# 跟 alpine-3.20/build.sh 一样的思路：docker run 出一个 container（这里不需要
# 起进程，docker create 就够），docker export 直接把 rootfs 拉出来。
say "create + export rootfs → $TARBALL"
CID="$(docker create --platform linux/amd64 "$TAG")"
trap 'docker rm -f "$CID" >/dev/null 2>&1 || true' EXIT
docker export "$CID" | gzip --best > "$TARBALL"
ok "rootfs ready"

# ---- 4. SHA256 + 尺寸 ----
SHA=$(shasum -a 256 "$TARBALL" 2>/dev/null | awk '{print $1}')
if [[ -z "$SHA" ]] && command -v sha256sum >/dev/null 2>&1; then
  SHA=$(sha256sum "$TARBALL" | awk '{print $1}')
fi
SIZE_TGZ=$(stat -f %z "$TARBALL" 2>/dev/null || stat -c %s "$TARBALL" 2>/dev/null)
echo "$SHA  $(basename "$TARBALL")" > "$TARBALL.sha256"

# ---- 5. 报告 ----
echo
echo "${B}=== build summary ===${O}"
printf "  name:    %s\n" "$NAME"
printf "  arch:    %s\n" "$ARCH"
printf "  tarball (gzip --best): %s MB\n" "$(awk -v s="$SIZE_TGZ" 'BEGIN{printf "%.1f", s/1024/1024}')"
printf "  sha256:  %s\n" "$SHA"
printf "  path:    %s\n" "$TARBALL"
echo
ok "done"
