#!/usr/bin/env bash
#
# Build Timberline for the Venu 2 family.
#
#   tools/build.sh                    # every device, strict type checking
#   tools/build.sh venu2              # just one
#   CIQ_SDK=~/my-sdk tools/build.sh   # point at a particular SDK
#
# Needs java and python3. The SDK is found automatically if you installed one
# with the graphical SDK Manager; otherwise set CIQ_SDK.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="$ROOT/build"
KEY="${CIQ_KEY:-$BUILD/developer_key.der}"
TYPECHECK="${CIQ_TYPECHECK:-3}"

# The Windows Store ships a `python3` stub that only prints an advert, so the
# interpreter is probed rather than just located.
if [ -z "${PYTHON:-}" ]; then
    for candidate in python3 python py; do
        if command -v "$candidate" >/dev/null 2>&1 &&
           "$candidate" -c "import sys" >/dev/null 2>&1; then
            PYTHON="$candidate"
            break
        fi
    done
fi
if [ -z "${PYTHON:-}" ]; then
    echo "no working python interpreter found; set PYTHON to one" >&2
    exit 1
fi

# Locate an SDK: an explicit CIQ_SDK, else the newest one the SDK Manager has
# unpacked under the user's Garmin folder.
SDK="${CIQ_SDK:-}"
if [ -z "$SDK" ]; then
    for base in "$HOME/AppData/Roaming/Garmin/ConnectIQ/Sdks" \
                "$HOME/Library/Application Support/Garmin/ConnectIQ/Sdks" \
                "$HOME/.Garmin/ConnectIQ/Sdks"; do
        if [ -d "$base" ]; then
            candidate="$(ls -1d "$base"/*/ 2>/dev/null | sort | tail -1 || true)"
            if [ -n "$candidate" ]; then
                SDK="${candidate%/}"
                break
            fi
        fi
    done
fi
if [ ! -f "$SDK/bin/monkeybrains.jar" ]; then
    echo "no Connect IQ SDK found; set CIQ_SDK to your SDK folder" >&2
    exit 1
fi

targets=("$@")
if [ ${#targets[@]} -eq 0 ]; then
    targets=(venu2)
fi

mkdir -p "$BUILD"

# A developer key signs the build. It is personal and never committed; any RSA
# key works for sideloading, and the store wants the one you registered with.
if [ ! -f "$KEY" ]; then
    echo "==> generating a developer key at $KEY"
    openssl genrsa -out "$BUILD/developer_key.pem" 4096 2>/dev/null
    openssl pkcs8 -topk8 -inform PEM -outform DER \
        -in "$BUILD/developer_key.pem" -out "$KEY" -nocrypt
fi

echo "==> generating the launcher icons"
"$PYTHON" "$ROOT/tools/make_icon.py" \
    "$ROOT/resources-round-416x416/drawables/launcher_icon.png" 70 >/dev/null
"$PYTHON" "$ROOT/tools/make_icon.py" \
    "$ROOT/resources-round-360x360/drawables/launcher_icon.png" 61 >/dev/null

echo "==> checking the round-screen layout"
"$PYTHON" "$ROOT/tools/check_layout.py"

status=0
for device in "${targets[@]}"; do
    echo "==> building $device"
    if java -jar "$SDK/bin/monkeybrains.jar" \
        --jungles "$ROOT/monkey.jungle" \
        --output "$BUILD/$device.prg" \
        --apidb "$SDK/bin/api.db" \
        --apimir "$SDK/bin/api.mir" \
        --device "$device" \
        --private-key "$KEY" \
        --typecheck "$TYPECHECK" \
        --warn; then
        echo "    $BUILD/$device.prg ($(wc -c <"$BUILD/$device.prg") bytes)"
    else
        status=1
    fi
done

exit $status
