#!/bin/bash
set -euo pipefail

root="$(cd "$(dirname "$0")" && pwd)"
target="${1:-device}"

command -v cargo >/dev/null 2>&1 || { echo "cargo is required to build rbit's pairing core" >&2; exit 1; }
command -v rustup >/dev/null 2>&1 || { echo "rustup is required to install the iOS Rust targets" >&2; exit 1; }

case "$target" in
  device)
    rust_target="aarch64-apple-ios"
    ;;
  simulator)
    rust_target="aarch64-apple-ios-sim"
    ;;
  *)
    echo "usage: $0 [device|simulator]" >&2
    exit 2
    ;;
esac

rustup target add "$rust_target"
cargo build --manifest-path "$root/Cargo.toml" --release --target "$rust_target"

mkdir -p "$root/out"
cp "$root/target/$rust_target/release/librbit_pairing_ffi.a" "$root/out/librbit_pairing_ffi-$target.a"
cp "$root/include/rbit_pairing.h" "$root/out/rbit_pairing.h"

echo "built rbit pairing core for $target"
