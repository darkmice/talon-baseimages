# code-browser flavor

Heavy baseimage for sandboxes that need a real browser engine — based on Debian
Trixie slim with **chromium + browser-harness + CJK fonts** preinstalled. Use
this only for sandboxes that actually need `POST /v1/sandboxes/{id}/browser`
(Spec 34) or `POST /v1/sandboxes/{id}/agent/run` (Spec 38). Default sandboxes
still use the much smaller `alpine-3.20` flavor.

## What's inside

- **Base** — Debian Trixie slim (`debian:trixie-slim`) — apt has well-maintained
  chromium packages; alpine's chromium-musl path has historical fontconfig /
  libstdc++ flakiness for headless mode.
- **Chromium** — `chromium` package; `chromium-browser` symlink for backward
  compatibility with the platform's binary detection list.
- **Fonts** — `fonts-noto-cjk` + `fonts-noto-color-emoji` + `fonts-liberation`
  so CJK and emoji render correctly in screenshots / screencast.
- **Chromium runtime libs** — `libnss3` `libxss1` `libasound2t64` `libatk*`
  `libcups2t64` `libxcomposite1` `libxdamage1` `libxrandr2` `libxkbcommon0`
  `libgbm1` `libpango-1.0-0` `libcairo2`.
- **Agent CDP tooling** — `python3` + `pip` + [`browser-harness`][bh] (thin
  ~1k LOC CDP wrapper, MIT) + `cdp-use` + `playwright`. Spec 34b chose
  browser-harness over browser-use because it's a **tool**, not an agent
  framework — users still pick their own agent layer.
- **Common shell** — bash / zsh / curl / wget / jq / git / openssh-client /
  nodejs / npm / sudo / tzdata / locales.
- **User** — non-root `agent` (uid 1000), aligned with runc adapter's user
  namespace mapping.

Expected size: **~700 MB** gzipped (vs ~70 MB for talon-alpine).

[bh]: https://github.com/browser-use/browser-harness

## Versioning

Independent from `alpine-3.20`. Tag format:

```
code-browser-v<MAJOR>.<MINOR>.<PATCH>
```

- **MAJOR** — chromium major bump that changes CDP capability surface, or
  Debian release change (trixie → forky → …).
- **MINOR** — added or removed packages.
- **PATCH** — security update of chromium / browser-harness without changing
  the set.

## Building locally

You need Docker (BuildKit not required).

```bash
bash code-browser/build.sh             # 0.1.0
VERSION=0.2.0 bash code-browser/build.sh
```

Outputs (in repo-root `out/`, shared with `alpine-3.20`):

```
out/talon-code-browser-<version>-x86_64.tar.gz
out/talon-code-browser-<version>-x86_64.tar.gz.sha256
```

First build downloads ~250 MB of chromium and takes 5-10 minutes. Subsequent
builds reuse docker layers.

## CI

Pushing a tag matching `code-browser-v*` triggers the shared
`.github/workflows/release.yml` and uploads the two assets to a release.

```bash
git tag code-browser-v0.1.0
git push origin code-browser-v0.1.0
```

## How sandbox-worker consumes it

Same path as the alpine flavor — the platform's `internal/runtime/baseimage`
package downloads the tarball, verifies the SHA-256, extracts it once per
worker, and each new sandbox hardlink-copies the extracted rootfs.

To register on the platform, either:

1. **Admin API** — `POST /v1/admin/images` with `url` + `sha256`.
2. **Env seed** — set on sandbox-api:
   ```
   SANDBOX_SEED_IMAGE_CODE_BROWSER_URL=https://github.com/darkmice/talon-baseimages/releases/download/code-browser-v0.1.0/talon-code-browser-0.1.0-x86_64.tar.gz
   SANDBOX_SEED_IMAGE_CODE_BROWSER_SHA256=<sha256>
   SANDBOX_SEED_IMAGE_CODE_BROWSER_NAME=code-browser-0.1.0
   ```

## Using with Docker / Podman

The release artifact is a **raw rootfs tarball** (top-level `bin/ etc/ usr/
home/ …`), not an OCI image archive. It is produced by `docker export`, not
`docker save` — so `docker pull` / `docker load` will not work. The platform's
runc adapter wants raw rootfs, but Docker accepts it too via `docker import`:

```bash
# 1. Download
curl -sfLo code-browser.tar.gz \
  https://github.com/darkmice/talon-baseimages/releases/download/code-browser-v0.1.0/talon-code-browser-0.1.0-x86_64.tar.gz

# 2. Verify (sha256 from the .sha256 sibling asset)
echo "<sha256>  code-browser.tar.gz" | sha256sum -c

# 3. Import as a docker image
docker import code-browser.tar.gz talon-code-browser:0.1.0

# 4. Sanity-run it
docker run --rm -it --platform linux/amd64 \
  talon-code-browser:0.1.0 \
  /bin/bash -c "chromium --version && python3 -c 'import browser_harness; print(browser_harness.__file__)'"
```

Notes:

- `docker import` drops image metadata (no ENV / CMD / ENTRYPOINT — the source
  was raw rootfs, not an image). Pass `--entrypoint` / explicit command at
  `docker run` time, or rebuild a thin wrapper image:
  ```dockerfile
  FROM talon-code-browser:0.1.0
  USER agent
  WORKDIR /home/agent
  CMD ["/bin/bash"]
  ```
- `--platform linux/amd64` matters on Apple Silicon / arm64 hosts — the
  tarball is x86_64 only; without it docker errors out instantly.
- `podman import` and `ctr image import --base-layer` work the same way for
  Podman and containerd respectively.
- This Docker workflow is for **ad-hoc inspection / sanity testing** — the
  intended consumer is still `agent-sandbox-platform`'s runc adapter via the
  env-seed mechanism above.

## Not in here

- **OCI image format** — we ship raw rootfs tarballs, same as the alpine
  flavor.
- **LLM SDKs** (openai / anthropic) — framework choice belongs in the agent
  layer; baseimage only ships tools.
- **LLM API keys** — injected at sandbox start via Spec 27 secrets.
- **X11 / VNC** — Spec 36 territory; this flavor is headless only.
