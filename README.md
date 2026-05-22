# talon-baseimages

Pre-built sandbox base images for [Talon Agent Sandbox](https://github.com/darkmice/agent-sandbox-platform).
Each "flavor" is a self-contained subdirectory that produces a raw rootfs
tarball + sha256, consumed by `internal/runtime/baseimage` on the platform side.

## Flavors

| Directory | Tag prefix | Asset name | Size (gzip) | Purpose |
|---|---|---|---|---|
| [`alpine-3.20/`](./alpine-3.20/) | `alpine-v` (or legacy `v`) | `talon-alpine-X.Y.Z-x86_64.tar.gz` | ~70 MB | **Default.** Lightweight alpine + bash/coreutils/git/curl/jq/python3/node 20. |
| [`code-browser/`](./code-browser/) | `code-browser-v` | `talon-code-browser-X.Y.Z-x86_64.tar.gz` | ~700 MB | Debian Trixie + chromium + browser-harness + CJK fonts. For sandboxes needing real browser automation (Spec 34 / Spec 38). |

CI: pushing a tag with the prefix above triggers
[`.github/workflows/release.yml`](.github/workflows/release.yml), which builds
the matching flavor on ubuntu-latest and uploads the two assets to a release.

## What's in `alpine-3.20`

See `alpine-3.20/packages.txt` for the authoritative package list. As of v0.1.0:

- **Shell** — `bash`, `coreutils`, `findutils`, `grep`, `sed`, `less`, `tar`
- **Crypto** — `ca-certificates`
- **Net/VCS** — `git`, `curl`, `wget`, `openssh-client`, `jq`
- **Python** — `python3`, `py3-pip` plus `python3-dev` + `gcc` + `musl-dev` + `linux-headers` so pip can fall back to compiling C extensions when no musl wheel exists
- **Node.js** — `nodejs` (Node 20), `npm` (corepack ships with npm so pnpm/yarn auto-activate)
- **Locale** — `tzdata`

Expected size: ~200 MB rootfs, ~70 MB gzipped tarball.

## Versioning (alpine flavor)

```
alpine-v<MAJOR>.<MINOR>.<PATCH>     # preferred
v<MAJOR>.<MINOR>.<PATCH>            # legacy, kept for backward compat
```
- **MAJOR** — Alpine major version change (e.g. 3.20 → 3.21 → 4.0) or breaking change for downstream consumers.
- **MINOR** — package set changes (added or removed packages).
- **PATCH** — upstream package version bumps without changing the set.

Releases are GitHub Releases on this repo with two assets:
```
talon-alpine-<version>-x86_64.tar.gz
talon-alpine-<version>-x86_64.tar.gz.sha256
```

(See [`code-browser/README.md`](./code-browser/README.md) for that flavor's
versioning rules — separate cadence.)

## How sandbox-worker consumes it

`agent-sandbox-platform`'s `internal/runtime/baseimage` package downloads the
tarball, verifies the SHA-256, and extracts it once per worker into a shared
cache directory. Each new sandbox `cp -al` (hardlink-copies) the extracted
rootfs, so the 200 MB cost is paid once per worker — not once per sandbox.

The platform pins the URL + SHA-256 in `internal/runtime/baseimage/baseimage.go`:

```go
var DefaultAlpine = Spec{
    Name:    "talon-alpine-3.20.0",
    URL:     "https://github.com/darkmice/talon-baseimages/releases/download/v0.1.0/talon-alpine-3.20.0-x86_64.tar.gz",
    SHA256:  "...",
}
```

## Using with Docker / Podman / containerd

The release artifact is a **raw rootfs tarball** (`bin/ etc/ usr/ home/ …` at
the top level), produced by `docker export` — not `docker save`. So
`docker pull` / `docker load` won't work. You import it instead:

```bash
# Pick whichever flavor + version you want
URL=https://github.com/darkmice/talon-baseimages/releases/download/code-browser-v0.1.0/talon-code-browser-0.1.0-x86_64.tar.gz

curl -sfLo image.tar.gz "$URL"
curl -sfL  "${URL}.sha256" | sha256sum -c -    # verify

# Docker
docker import image.tar.gz talon-code-browser:0.1.0

docker run --rm -it --platform linux/amd64 \
  talon-code-browser:0.1.0 \
  bash -c "chromium --version"

# Podman / containerd are analogous
podman import image.tar.gz talon-code-browser:0.1.0
ctr image import --base-layer image.tar.gz docker.io/library/talon-code-browser:0.1.0
```

Caveats:

- `docker import` drops image metadata (no `ENV`/`CMD`/`ENTRYPOINT`) — pass
  them via `docker run`, or build a thin wrapper `FROM talon-code-browser:…`.
- `--platform linux/amd64` matters on Apple Silicon / arm64 hosts; tarballs
  are x86_64 only.
- Intended consumer is still `agent-sandbox-platform`'s runc adapter — Docker
  is for ad-hoc inspection / sanity checks. See per-flavor README for the
  flavor-specific runtime layout.

## Building locally

You need Docker; each flavor's `build.sh` runs the base image in a throwaway
container (or `docker build` for `code-browser`), then `docker export`s the
result.

```bash
# alpine flavor
bash alpine-3.20/build.sh                       # → out/talon-alpine-3.20.0-x86_64.tar.gz
VERSION=3.20.1 bash alpine-3.20/build.sh        # specific patch

# code-browser flavor
bash code-browser/build.sh                      # → out/talon-code-browser-0.1.0-x86_64.tar.gz
VERSION=0.2.0 bash code-browser/build.sh
```

The shared `out/` directory at repo root collects both flavors' artifacts.

## CI

`.github/workflows/release.yml` is shared across flavors. Tag prefixes route
to the matching `build.sh`. Manual runs via `workflow_dispatch` require
choosing the flavor + version explicitly.

## License

See `LICENSE`. The contained Alpine binaries each retain their upstream license.
