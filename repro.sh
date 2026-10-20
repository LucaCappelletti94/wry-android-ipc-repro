#!/usr/bin/env bash
# Usage: ./repro.sh <baseline|pr> [runs] [stall_ms] [slice_ms]
# Builds the app against the chosen wry, installs it on $ANDROID_SERIAL and
# cold-starts it `runs` times, printing the outcome of the page's first IPC call.
set -euo pipefail
variant=${1:?baseline or pr}
runs=${2:-10}
stall_ms=${3:-3000}
slice_ms=${4:-100}
cd "$(dirname "$0")"
: "${ANDROID_SERIAL:?set ANDROID_SERIAL to the emulator or device serial}"
export ANDROID_SERIAL
app=com.example.wryipcrepro

cat stall.toml "variants/$variant.toml" > .cargo/config.toml
if [ -z "${SKIP_BUILD:-}" ]; then
  [ -d gen/android ] || cargo tauri android init
  export CARGO_TARGET_DIR="target/$variant"
  cargo tauri android build --debug --apk -t "${TARGET:-x86_64}" >&2
  # Only the PR's Ipc.kt uses addWebMessageListener; catches a stale generated file.
  listener=$(grep -c addWebMessageListener gen/android/app/src/main/java/com/example/wryipcrepro/generated/Ipc.kt || true)
  if { [ "$variant" = pr ] && [ "$listener" = 0 ]; } || { [ "$variant" = baseline ] && [ "$listener" != 0 ]; }; then
    echo "generated Ipc.kt does not match $variant" >&2
    exit 1
  fi
  adb install -r gen/android/app/build/outputs/apk/universal/debug/app-universal-debug.apk >/dev/null
fi

ok=0 err=0
for i in $(seq 1 "$runs"); do
  adb shell am force-stop "$app"
  adb logcat -c
  adb shell am start -W -n "$app/.MainActivity" --ei stall_ms "$stall_ms" --ei slice_ms "$slice_ms" >/dev/null
  line=""
  for _ in $(seq 1 60); do
    line=$(adb logcat -d -s Tauri/Console:I | grep -m1 -o 'REPRO IPC-[A-Z]*.*' || true)
    [ -n "$line" ] && break
    sleep 0.5
  done
  echo "run $i: ${line:-no result within 30s}"
  case "$line" in
    "REPRO IPC-OK"*) ok=$((ok + 1)) ;;
    "REPRO IPC-ERR"*) err=$((err + 1)) ;;
  esac
done
echo "$variant stall_ms=$stall_ms slice_ms=$slice_ms: $ok IPC-OK, $err IPC-ERR, $((runs - ok - err)) no result"
