# Moonlight-spruce

Cross-compiled [moonlight-embedded](https://github.com/moonlight-stream/moonlight-embedded) builds for [spruceOS](https://github.com/spruceUI/spruceOS).

## Builds

| Build | Output | Devices | Base |
|-------|--------|---------|------|
| Universal | `moonlight-aarch64.tar.gz` | Brick, TSP, TSPS, Flip, Pixel2 | Ubuntu 20.04 (glibc 2.31) |

## Usage

Builds are triggered manually via GitHub Actions (`workflow_dispatch`). Binaries are uploaded to per-branch beta prereleases.

```bash
# Trigger a build
gh workflow run build-all.yml

# Download the output
gh release download beta-main -p "moonlight-aarch64.tar.gz"
```

## Output structure

```
moonlight           # moonlight-embedded binary
libs/               # All required shared libraries
```

## Build dependencies (from source)

- **OpenSSL 3.3.1** — cross-compiled for aarch64
- **curl 8.7.1** — built against our OpenSSL
- **moonlight-embedded** — built against all of the above + system arm64 libs

System arm64 libraries (FFmpeg, PulseAudio, Opus, etc.) come from Ubuntu 20.04's multiarch repos.
