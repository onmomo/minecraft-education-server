#!/usr/bin/env bash
#
# Bootstraps the /data volume on first run, then execs the Minecraft
# Education dedicated server.
#
#   * Files in INIT_PATHS are *copied* from the image to /data on first
#     run only — they are user-editable and survive container restarts.
#   * Paths in LINK_PATHS are *symlinked* into /data on every run, so
#     image updates (new server version) propagate automatically.

set -euo pipefail

SERVER_DIR=/opt/mcedu
DATA_DIR=/data

INIT_PATHS=(
    server.properties
    allowlist.json
    permissions.json
    packetlimitconfig.json
)

LINK_PATHS=(
    bedrock_server_edu
    bedrock_server_how_to.html
    release-notes.txt
    profanity_filter.wlist
    behavior_packs
    resource_packs
    definitions
    config
)

log() { printf '[entrypoint] %s\n' "$*"; }
die() { printf '[entrypoint] ERROR: %s\n' "$*" >&2; exit 1; }

if [[ ! -d "$DATA_DIR" ]]; then
    die "$DATA_DIR does not exist — mount a volume there."
fi

# The server writes edu_server_session.json (the device-code credential
# blob) and the worlds/ tree into its cwd. If /data is not writable for
# both files and directories we'll fail later with a confusing "Check
# if you have permissions to read the credential file" message — fail
# loudly here with a precise hint instead.
probe="$DATA_DIR/.entrypoint_probe.$$"
if ! ( : > "$probe.file" && mkdir "$probe.dir" ) 2>/dev/null; then
    rm -rf "$probe.file" "$probe.dir" 2>/dev/null || true
    die "$DATA_DIR is not writable by uid $(id -u). On the host: chown -R 1000:1000 ./data && chmod -R u+rwX ./data"
fi
rm -rf "$probe.file" "$probe.dir"

mkdir -p "$DATA_DIR/worlds"

for p in "${INIT_PATHS[@]}"; do
    if [[ ! -e "$DATA_DIR/$p" ]]; then
        log "seeding default: $p"
        cp -r "$SERVER_DIR/$p" "$DATA_DIR/$p"
    fi
done

for p in "${LINK_PATHS[@]}"; do
    target="$DATA_DIR/$p"
    if [[ -L "$target" ]]; then
        rm -f "$target"
    elif [[ -e "$target" ]]; then
        # User has placed a real file/dir here — leave it alone so they
        # can override behavior_packs/resource_packs/etc.
        continue
    fi
    ln -s "$SERVER_DIR/$p" "$target"
done

cd "$DATA_DIR"
export LD_LIBRARY_PATH=.

log "starting bedrock_server_edu"
exec ./bedrock_server_edu "$@"
