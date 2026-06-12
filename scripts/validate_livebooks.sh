#!/usr/bin/env bash
set -euo pipefail

shopt -s nullglob
livebooks=(livebooks/*.livemd)

if [ ${#livebooks[@]} -eq 0 ]; then
  echo "no livebooks found in livebooks/" >&2
  exit 1
fi

if grep -R -q 'path: "\."' livebooks/; then
  echo "livebooks must not use Mix.install path: \".\" (use Path.expand(\"..\", __DIR__))" >&2
  exit 1
fi

if ! grep -q 'Path\.expand("\.\.", __DIR__)' "${livebooks[@]}"; then
  echo "livebooks must install ex_azure from the repo root via Path.expand" >&2
  exit 1
fi

echo "Livebook paths look valid."
