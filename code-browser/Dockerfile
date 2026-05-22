# code-browser baseimage —— Spec 34b.
#
# 产物：一个 ~700MB 的 rootfs tarball，包含：
#   - Debian trixie-slim 基底（apt 生态比 alpine 的 chromium 路径稳）
#   - chromium + 完整字体（CJK + emoji）+ runtime 依赖 (nss / xss / asound)
#   - python3 + pip + browser-harness（Spec 34b §2 的核心工具）
#   - 与 alpine-3.20 相同的"代理工具集"：bash / curl / wget / jq / git / openssh-client / ca-certs
#   - 一个非 root 用户 agent (uid 1000) — 与 runc adapter 的 user namespace 默认 uid 对齐
#
# 与同仓 alpine-3.20 flavor 的关系：
#   - 输出格式一致（裸 rootfs tar.gz / sha256 校验），由 sandbox-worker 的
#     internal/runtime/baseimage 直接消费
#   - 它不替换 talon-alpine：default 仍是 talon-alpine（轻量），code-browser 给
#     需要 chromium 的 sandbox 显式选

FROM debian:trixie-slim AS rootfs

# 关闭交互、确保 https 仓库 / 字体路径都准备好
ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8

# Layer 1: 平台常用工具 + 网络 + python + node 运行时 ——
# 这部分是"agent 工位"的基础，与 alpine-3.20 的诉求一致；用 Debian apt 装最稳。
RUN apt-get update && apt-get install -y --no-install-recommends \
      bash zsh \
      ca-certificates curl wget jq \
      git openssh-client \
      python3 python3-pip python3-venv \
      nodejs npm \
      tzdata locales \
      sudo \
    && rm -rf /var/lib/apt/lists/*

# Layer 2: chromium + 字体 + chromium 运行时依赖。
# Debian 的 chromium 包名就是 chromium（不是 chromium-browser，那是 Ubuntu）；
# 容器内 PATH 上同时建一个 chromium-browser symlink 兼容 spec 34 的探测列表。
RUN apt-get update && apt-get install -y --no-install-recommends \
      chromium \
      fonts-noto-cjk fonts-noto-color-emoji fonts-liberation \
      libnss3 libxss1 libasound2t64 libatk1.0-0t64 libatk-bridge2.0-0t64 \
      libcups2t64 libxcomposite1 libxdamage1 libxrandr2 libxkbcommon0 \
      libgbm1 libpango-1.0-0 libcairo2 \
    && rm -rf /var/lib/apt/lists/* \
    && if [ -x /usr/bin/chromium ] && [ ! -e /usr/bin/chromium-browser ]; then \
         ln -s /usr/bin/chromium /usr/bin/chromium-browser; \
       fi

# Layer 3: browser-harness（spec 34b §2 选用——薄壳 CDP 工具，非 framework）。
# 注意：browser-use/browser-harness 不在 PyPI，pip 直接装 git+ URL。
# 使用 --break-system-packages 是因为 Debian Trixie PEP 668 默认禁止系统级 pip
# 安装；agent sandbox 内我们自己的镜像，绕开这个限制是合理的——本来就不是
# 给用户 host 上跑。
RUN pip install --no-cache-dir --break-system-packages \
      "browser-harness @ git+https://github.com/browser-use/browser-harness@main" \
      cdp-use \
      playwright

# Layer 4: 非 root 用户 agent (uid 1000)。
# runc adapter 默认在 user namespace 把 host uid map 到 container uid 1000，
# 与这里对齐能让 sandbox 内 home / workspace 文件权限正确。
RUN useradd -m -u 1000 -s /bin/bash agent \
    && mkdir -p /home/agent/.config/chromium /home/agent/.cache \
    && chown -R agent:agent /home/agent

# 抹掉 apt cache / man / doc 让 rootfs 小一些
RUN rm -rf \
      /var/lib/apt/lists/* \
      /usr/share/doc/* \
      /usr/share/man/* \
      /var/cache/apt/* \
      /tmp/*

FROM rootfs AS final
WORKDIR /
