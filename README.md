# talon-baseimages

Pre-built sandbox base images for [Talon Agent Sandbox](https://github.com/darkmice/agent-sandbox-platform).
A small Alpine-based rootfs bundling the runtime tooling an AI agent typically
needs (bash, GNU coreutils, git, curl, jq, python3 + pip, node 20 + npm, …) so
each new sandbox starts with a usable environment instead of a 3.5 MB busybox-only
minirootfs.

## What's inside

See `alpine-3.20/packages.txt` for the authoritative package list. As of v0.1.0:

- **Shell** — `bash`, `coreutils`, `findutils`, `grep`, `sed`, `less`, `tar`
- **Crypto** — `ca-certificates`
- **Net/VCS** — `git`, `curl`, `wget`, `openssh-client`, `jq`
- **Python** — `python3`, `py3-pip` plus `python3-dev` + `gcc` + `musl-dev` + `linux-headers` so pip can fall back to compiling C extensions when no musl wheel exists
- **Node.js** — `nodejs` (Node 20), `npm` (corepack ships with npm so pnpm/yarn auto-activate)
- **Locale** — `tzdata`

Expected size: ~200 MB rootfs, ~70 MB gzipped tarball.

## Versioning

```
v<MAJOR>.<MINOR>.<PATCH>
```
- **MAJOR** — Alpine major version change (e.g. 3.20 → 3.21 → 4.0) or breaking change for downstream consumers.
- **MINOR** — package set changes (added or removed packages).
- **PATCH** — upstream package version bumps without changing the set.

Releases are GitHub Releases on this repo with two assets:
```
talon-alpine-<version>-x86_64.tar.gz
talon-alpine-<version>-x86_64.tar.gz.sha256
```

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

## Building locally

You need Docker; the script runs `alpine:3.20` in a throwaway container, installs
packages, and `docker export`s the result.

```bash
bash alpine-3.20/build.sh
# → out/talon-alpine-3.20.0-x86_64.tar.gz
# → out/talon-alpine-3.20.0-x86_64.tar.gz.sha256
```

A specific patch version:
```bash
VERSION=3.20.1 bash alpine-3.20/build.sh
```

## CI

Pushing a tag matching `v*` triggers `.github/workflows/release.yml`, which runs
`build.sh` on Ubuntu and uploads the two assets to the release. See that file
for details.

## License

See `LICENSE`. The contained Alpine binaries each retain their upstream license.
