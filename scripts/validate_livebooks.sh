#!/usr/bin/env bash
set -euo pipefail

if rg -q 'path: "\."' livebooks/; then
  echo "livebooks must not use Mix.install path: \".\" (use Path.expand(\"..\", __DIR__))" >&2
  exit 1
fi

if ! rg -q 'Path\.expand\("\.\.", __DIR__\)' livebooks/*.livemd; then
  echo "livebooks must install ex_azure from the repo root via Path.expand" >&2
  exit 1
fi

echo "Livebook paths look valid."
