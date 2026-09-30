#!/usr/bin/env bash
# Livebooks ship in the Hex package and HexDocs, so they must install azure_sdk
# from Hex at the current minor version. A local path dependency may only
# appear commented out (for development inside the repository).
set -euo pipefail

shopt -s nullglob
livebooks=(livebooks/*.livemd)

if [ ${#livebooks[@]} -eq 0 ]; then
  echo "no livebooks found in livebooks/" >&2
  exit 1
fi

version=$(sed -n 's/^  @version "\([0-9]*\.[0-9]*\)\.[0-9]*"$/\1/p' mix.exs)

if [ -z "$version" ]; then
  echo "could not read @version from mix.exs" >&2
  exit 1
fi

status=0

for livebook in "${livebooks[@]}"; do
  if grep -Eq '^[[:space:]]*\{:azure_sdk, path:' "$livebook"; then
    echo "$livebook: uncommented path dependency; install from Hex instead" >&2
    status=1
  fi

  if ! grep -Fq "{:azure_sdk, \"~> ${version}." "$livebook"; then
    echo "$livebook: must install {:azure_sdk, \"~> ${version}.x\"} (mix.exs is ${version})" >&2
    status=1
  fi
done

if [ "$status" -eq 0 ]; then
  echo "Livebook dependencies look valid (azure_sdk ~> ${version})."
fi

exit "$status"
