#!/usr/bin/env sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
OUT="$ROOT/Sources/TelegrapheCore/Generated"
mkdir -p "$OUT"
protoc --swift_out="$OUT" "$ROOT/proto/telegraphe.proto"
