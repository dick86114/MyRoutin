#!/usr/bin/env bash
set -euo pipefail

xcode_output="$(xcodebuild -version)"
xcode_version="$(printf '%s\n' "$xcode_output" | awk '/^Xcode / { print $2; exit }')"
if [[ "${xcode_version%%.*}" -lt 26 ]]; then
  echo "错误：构建需要 Xcode 26 或更高版本，当前为 ${xcode_version:-未知版本}。" >&2
  exit 1
fi

sdk_version="$(xcrun --sdk macosx --show-sdk-version)"
if [[ "${sdk_version%%.*}" -lt 26 ]]; then
  echo "错误：构建需要 macOS 26 SDK 或更高版本，当前为 ${sdk_version:-未知版本}。" >&2
  exit 1
fi

printf '已验证 Xcode %s，macOS SDK %s。\n' "$xcode_version" "$sdk_version"
