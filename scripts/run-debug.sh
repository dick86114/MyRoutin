#!/bin/bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
derived_path="$repo_root/.build/debug-derived"
app_path="$derived_path/Build/Products/Debug/MyToken.app"

cd "$repo_root"
xcodegen generate
xcodebuild \
  -project RoutinUsage.xcodeproj \
  -scheme RoutinUsage \
  -configuration Debug \
  -derivedDataPath "$derived_path" \
  build

codesign --verify --deep --strict "$app_path"
pkill -x MyToken 2>/dev/null || true
open -n "$app_path"
