# docker-minecraft-education-server

A Docker wrapper for the official **Minecraft Education** dedicated server
(Linux). Persists worlds and configuration to a host volume, lets you tweak
`server.properties` and friends with a normal text editor, and survives
container restarts.

The dedicated server zip is downloaded from Microsoft's official CDN at
build time (default: <https://aka.ms/downloadmee-linuxserver>, as
documented in the [Tooling and Scripting Guide][1]). The proprietary
binary is **not** included in this repo.

[1]: https://edusupport.minecraft.net/hc/en-us/articles/41757415076884-Dedicated-Server-Tooling-and-Scripting-Guide

References:
- [Dedicated Server FAQ](https://edusupport.minecraft.net/hc/en-us/articles/41758309283348-Dedicated-Server-FAQ)
- [Dedicated Server Tooling and Scripting Guide](https://edusupport.minecraft.net/hc/en-us/articles/41757415076884-Dedicated-Server-Tooling-and-Scripting-Guide)

## Requirements

- Docker 24+ with Compose v2 and BuildKit (default in modern Docker)
- The image is built for `linux/amd64`. The Microsoft `bedrock_server_edu`
  binary is x86_64-only — there is no arm64 build. Apple Silicon Macs
  run it under Rosetta emulation; arm64 Linux hosts need qemu-user. See
  [Building on macOS / Apple Silicon](#building-on-macos--apple-silicon).
- ~1 GB free disk for the image, plus space for your worlds

## Quick start

### Option A — pull the published image (recommended)

Released images are pushed to Docker Hub at
[`onmomo/minecraft-education-server`](https://hub.docker.com/r/onmomo/minecraft-education-server)
and tagged with both the wrapper version (`vX.Y.Z`) and the upstream
MEE version (`mee-1.21.133.2`):

```bash
mkdir -p data
docker run -d --name minecraft-edu \
  --platform linux/amd64 \
  --restart unless-stopped \
  -p 20202:20202/udp \
  -p 19132:19132/udp \
  -v "$PWD/data:/data" \
  -it \
  onmomo/minecraft-education-server:latest
```

Or with compose, using the bundled `docker-compose.pull.yml` override
that swaps the build for an image pull:

```bash
docker compose -f docker-compose.yml -f docker-compose.pull.yml up -d
```

### Option B — build it yourself

```bash
git clone <this-repo> docker-minecraft-edu
cd docker-minecraft-edu
cp .env.example .env          # tweak ports if needed
docker compose up -d --build
```

That's it. The build will:

1. Download `MinecraftEducation_LinuxDS_*.zip` from
   <https://aka.ms/downloadmee-linuxserver>.
2. Extract it into `/opt/mcedu` inside the image.
3. Build a small Ubuntu 22.04 runtime layer with `tini` and a non-root
   `mcedu` user.

On first start the entrypoint copies the default editable config files
(`server.properties`, `allowlist.json`, `permissions.json`,
`packetlimitconfig.json`) into `./data/`. Read-only assets
(`behavior_packs`, `resource_packs`, `definitions`, `config`,
`bedrock_server_edu`, `profanity_filter.wlist`) are symlinked from the
image, so a `docker compose build --no-cache && docker compose up -d`
is enough to pick up a new upstream server version.

Connect from a Minecraft Education client to the host's IP on UDP port
`20202` (the bundle's default — change in `server.properties` if you
want).

### Build without compose

```bash
docker buildx build --platform linux/amd64 --load -t docker-minecraft-edu .

docker run -d --name minecraft-edu \
  --platform linux/amd64 \
  -p 20202:20202/udp \
  -p 19132:19132/udp \
  -v "$PWD/data:/data" \
  -it \
  docker-minecraft-edu
```

## Building on macOS / Apple Silicon

The shipped `docker-compose.yml` already pins `platform: linux/amd64`
for both build and run, so on an M-series Mac:

```bash
docker compose up -d --build
```

… just works. Docker Desktop builds the image for `linux/amd64` (using
qemu under the hood) and runs the resulting container with Rosetta
translating the x86_64 instructions. Confirmed end-to-end on Apple
Silicon: the server boots, opens UDP/20202, and reaches the Microsoft
device-code auth flow.

If you prefer the plain `docker` CLI on macOS:

```bash
# One-time: make sure the buildx amd64 builder exists.
docker buildx create --name xbuilder --use --bootstrap 2>/dev/null || true

# Build for amd64 specifically (the default would otherwise be arm64
# on Apple Silicon, which the bedrock binary cannot run).
docker buildx build --platform linux/amd64 --load -t docker-minecraft-edu .

# Run, pinning the platform.
docker run -d --name minecraft-edu \
  --platform linux/amd64 \
  -p 20202:20202/udp -p 19132:19132/udp \
  -v "$PWD/data:/data" -it \
  docker-minecraft-edu
```

> **Performance.** Rosetta x86_64 emulation costs ~10-20% CPU vs
> native. Fine for a classroom-sized server; if you're hitting CPU
> limits, run on an x86_64 host (e.g. a Linux VM, a NUC, or any cloud
> amd64 instance).

## Pinning a specific server version

The default `BUNDLE_URL` (the aka.ms redirect) tracks "latest". For
reproducible builds, resolve it once and pin to the versioned URL:

```bash
curl -sIL -o /dev/null -w '%{url_effective}\n' https://aka.ms/downloadmee-linuxserver
# → https://downloads.minecrafteduservices.com/retailbuilds/LinuxDS/MinecraftEducation_LinuxDS_1.21.133.2.zip

curl -fSL -o bundle.zip "<that URL>"
sha256sum bundle.zip
```

Then in `.env`:

```env
BUNDLE_URL=https://downloads.minecrafteduservices.com/retailbuilds/LinuxDS/MinecraftEducation_LinuxDS_1.21.133.2.zip
BUNDLE_SHA256=<hex from sha256sum>
```

## Configuration

After the first start, edit files under `./data/`:

| File                     | What it controls                                      |
| ------------------------ | ----------------------------------------------------- |
| `server.properties`      | Port, gamemode, difficulty, max players, view dist…   |
| `allowlist.json`         | Allowlist (when `allow-list=true`)                    |
| `permissions.json`       | Per-player operator/visitor permissions               |
| `packetlimitconfig.json` | Packet rate limiting (when enabled)                   |

Restart to apply:

```bash
docker compose restart
```

Worlds live under `./data/worlds/<level-name>/`.

> ⚠️ The default `server-public-ip=localhost` only works if client and
> server run on the same machine. Edit `data/server.properties` — its
> inline comments explain the LAN / public-IP cases. Restart to apply.

### Resetting a config file

To get the shipped default of a file back, delete it and restart — the
entrypoint reseeds anything missing on next launch:

```bash
rm data/server.properties
docker compose restart
```

### Environment variables

`.env` keys understood by `docker-compose.yml` (see `.env.example`):

| Key             | Purpose                                                                |
| --------------- | ---------------------------------------------------------------------- |
| `BUNDLE_URL`    | Source of the dedicated server zip. Defaults to the aka.ms redirect.  |
| `BUNDLE_SHA256` | Optional integrity check. Recommended when pinning `BUNDLE_URL`.       |
| `MCEDU_PORT`    | Host UDP port published to clients. Match `server-port` in properties. |
| `MCEDU_LAN_PORT`| Host UDP port for LAN visibility (server also binds 19132).            |
| `IMAGE_TAG`     | Image tag used by `docker compose build`.                              |

If you change `MCEDU_PORT` you must also set the same value as
`server-port=` inside `data/server.properties` — the published port and
the server's listening port have to agree.

### Private mirrors / auth headers

If you mirror the bundle behind a token-protected URL, pass the auth
header as a BuildKit secret instead of baking it into image history:

```bash
echo "Bearer $TOKEN" | docker buildx build \
  --secret id=bundle_auth,src=/dev/stdin \
  --build-arg BUNDLE_URL=https://internal.example.com/bundle.zip \
  --build-arg BUNDLE_SHA256=<hex> \
  -t docker-minecraft-edu .
```

## First-time sign-in (Microsoft device-code flow)

The first time you start the server it has no credentials, so it prints
a Microsoft device-login URL + code and **blocks** until an admin
completes the auth. From the docs ([Tooling and Scripting Guide][1]):

> The server stores session info in `edu_server_session.json` so it can
> attempt a silent token refresh on restart. If silent refresh fails,
> it prompts to sign in again.

Step by step:

1. **Watch the logs** for the device-code prompt:

   ```bash
   docker compose logs -f mcedu
   ```

   You'll see something like:

   ```
   To sign in, use a web browser to open the page
   https://microsoft.com/devicelogin and enter the code XXXXXXXX
   to authenticate.
   ```

   A convenience helper:

   ```bash
   scripts/show-login-code.sh
   ```

2. Open that URL in any browser, enter the code, and **sign in as a
   Global Admin of your tenant**. When asked, confirm you are signing
   in to **"Minecraft Education Admin Tools"** and click *Continue*.

3. The server completes auth and writes `./data/edu_server_session.json`
   on your host. From now on it can refresh tokens silently — restarts
   no longer require browser interaction.

### Where credentials live

| File                              | Contents                                  | Persists? |
| --------------------------------- | ----------------------------------------- | --------- |
| `data/edu_server_session.json`    | Refresh token + server ID                 | Yes — survives container/image rebuild because it lives on the host volume. |

The credential file is sensitive. Treat it like any refresh-token blob:
do **not** commit it, do **not** copy it to chat, and rotate it (delete
+ re-auth) if it leaks. The shipped `.gitignore` excludes it.

### Re-authenticating

Force a fresh sign-in (e.g. when the tenant admin changes, after a
suspected leak, or when silent refresh repeatedly fails):

```bash
docker compose down
rm data/edu_server_session.json
docker compose up -d
docker compose logs -f mcedu        # grab the new device code
```

### Migrating to another host

Copy `data/edu_server_session.json` (and the rest of `data/`, including
`worlds/`) to the new host. The new server identifies itself with the
same server ID and skips device-code on first start.

### Looking up the server ID

The Tooling and Scripting Guide notes the server ID is also recorded
inside `edu_server_session.json` if you lose track of it elsewhere:

```bash
jq -r '.serverId // .server_id // .' data/edu_server_session.json | head
```

## Build provenance from inside the container

Three build-time facts are baked into the running image so you can
check them from any shell, including `docker exec`:

```bash
docker exec minecraft-edu sh -c \
  'echo "BUNDLE_URL=$BUNDLE_URL"
   echo "BUNDLE_SHA256=$BUNDLE_SHA256"
   echo "MEE_VERSION=$(cat /opt/mcedu/.mee_version)"'
```

`BUNDLE_URL` and `BUNDLE_SHA256` are real env vars; the parsed MEE
version is in `/opt/mcedu/.mee_version`. (The same MEE version is also
in the bedrock server's startup logs.)

## Server console

Server commands (`say hello`, `op <player>`, `stop`, …) are read from
stdin. Attach to the container's TTY:

```bash
docker attach minecraft-edu
```

Detach without stopping the server: **Ctrl-P Ctrl-Q**.
Avoid Ctrl-C — that kills the server.

## Updating to a new server version

1. `docker compose build --no-cache && docker compose up -d`
2. Your `data/` is preserved. Read-only assets (behavior packs,
   resource packs, definitions, the binary itself) update automatically
   because they are symlinked. Editable config files are not
   overwritten — delete them first if you want to pick up new defaults.

If you pinned `BUNDLE_URL`/`BUNDLE_SHA256`, update them in `.env` first.

## Releases & versioning

Tagged releases follow [Semantic Versioning](https://semver.org/) on the
**wrapper**, independent of the upstream server version:

```bash
git tag -a v0.1.0 -m "Initial release"
git push origin v0.1.0
```

Pushing a `v*` tag triggers `.github/workflows/release.yml`, which:

1. Resolves `BUNDLE_URL` (repo secret if set, otherwise the aka.ms
   default) to the versioned CDN URL, e.g.
   `…/MinecraftEducation_LinuxDS_1.21.133.2.zip`.
2. Downloads the zip and computes its SHA-256.
3. Creates a GitHub Release titled `vX.Y.Z (MEE 1.21.133.2)`. The
   release body records the upstream MEE version, the resolved bundle
   URL, the SHA-256, and pull commands for the published image.
4. Builds the image and pushes it to
   [`onmomo/minecraft-education-server`](https://hub.docker.com/r/onmomo/minecraft-education-server)
   on Docker Hub with three tags:
   - `onmomo/minecraft-education-server:<wrapper-tag>` — e.g. `v0.1.0`
   - `onmomo/minecraft-education-server:mee-<upstream>` — e.g. `mee-1.21.133.2`
   - `onmomo/minecraft-education-server:latest`

Every release is explicitly tied to the upstream MEE server version it
wraps — no need to remember to put it in the tag message.

## Project layout

```
.
├── Dockerfile                   # 2-stage: fetcher + ubuntu:22.04 runtime
├── docker-compose.yml
├── docker/
│   └── entrypoint.sh            # seeds /data, symlinks read-only assets
├── scripts/
│   └── show-login-code.sh       # tail logs for the device-code prompt
├── .github/workflows/
│   ├── ci.yml                   # hadolint + shellcheck
│   └── release.yml              # tag → GitHub Release
├── .gitignore                   # excludes the bundle, data/, .env
├── .dockerignore
├── .env.example
└── README.md
```

## Troubleshooting

**`rosetta error: failed to open elf at /lib64/ld-linux-x86-64.so.2`.**
You built or ran the image without pinning to `linux/amd64`, so on
Apple Silicon Docker chose arm64 — but the bedrock binary is x86_64
only. Rebuild with `--platform linux/amd64` (compose already does
this); see [Building on macOS / Apple Silicon](#building-on-macos--apple-silicon).

**`sha256sum: WARNING: 1 computed checksum did NOT match`.** The server
zip on Microsoft's CDN was rebuilt and your pinned `BUNDLE_SHA256` no
longer matches. Either pin to a new versioned URL or remove the pin to
fall back to "latest".

**Clients can't connect.** Check that the host firewall allows
`UDP/${MCEDU_PORT}` and that `server-public-ip` in `server.properties`
matches the address clients use to reach you. For internet-facing
servers set it to your public IP and forward UDP from your router.

**Permission errors writing to `data/`.** The container runs as UID
1000. Either run with a host user that has UID 1000, or chown:

```bash
sudo chown -R 1000:1000 data/
```

**Server exits immediately.** Tail the logs: `docker compose logs -f`.
The most common cause is a malformed `server.properties` value —
restore the default by deleting the file and restarting (see
[Resetting a config file](#resetting-a-config-file)).
