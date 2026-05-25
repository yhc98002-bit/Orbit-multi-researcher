#!/usr/bin/env bash
set -euo pipefail

prefix="${1:-$HOME/.local}"
bin_dir="$prefix/bin"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"

mkdir -p "$bin_dir"
ln -sfn "$script_dir/bin/orbit" "$bin_dir/orbit"

printf 'Installed orbit -> %s/orbit\n' "$bin_dir"
printf 'Add to PATH if needed: export PATH="%s:$PATH"\n' "$bin_dir"
