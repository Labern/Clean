#!/bin/sh
# Runs cargo with the private toolchain (it has the Windows and Linux targets), from this folder.
#   ./cargo.sh test                       core + drawing tests on this machine
#   ./cargo.sh check --target x86_64-pc-windows-msvc -p focus     type-check the Windows app from a Mac
cd "$(dirname "$0")" || exit 1
R="$HOME/Library/Caches/focus-port-rust"
if [ -x "$R/cargo/bin/cargo" ]; then
  export RUSTUP_HOME="$R/rustup" CARGO_HOME="$R/cargo" PATH="$R/cargo/bin:$PATH"
fi
exec cargo "$@"
