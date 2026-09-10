#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
repo_root="$(cd -- "$script_dir/.." && pwd -P)"

if [[ ! -f "$repo_root/project.yml" ]]; then
  echo "错误：脚本所在仓库未找到 project.yml。" >&2
  exit 1
fi

build_root="$repo_root/build"
dist_dir="$build_root/dist"
derived_data_dir="$build_root/DerivedData"
staging_dir="$build_root/DMGStaging"

if [[ -L "$build_root" ]]; then
  echo "错误：build 不能是符号链接，已拒绝清理。" >&2
  exit 1
fi

canonical_path() {
  local target="$1"
  local existing="$target"
  local suffix=""
  local parent

  while [[ ! -e "$existing" && ! -L "$existing" ]]; do
    suffix="/$(basename -- "$existing")$suffix"
    existing="$(dirname -- "$existing")"
  done

  if [[ -d "$existing" ]]; then
    existing="$(cd -- "$existing" && pwd -P)"
  else
    parent="$(cd -- "$(dirname -- "$existing")" && pwd -P)"
    existing="$parent/$(basename -- "$existing")"
  fi
  printf '%s%s\n' "$existing" "$suffix"
}

assert_inside_repo() {
  local target="$1"
  local canonical
  canonical="$(canonical_path "$target")"
  case "$canonical" in
    "$repo_root"/*) ;;
    *)
      echo "错误：清理目标位于仓库外：$canonical" >&2
      exit 1
      ;;
  esac
}

assert_inside_repo "$dist_dir"
assert_inside_repo "$derived_data_dir"
assert_inside_repo "$staging_dir"

if [[ "${ROUTIN_DMG_DRY_RUN:-0}" == "1" ]]; then
  echo "仓库根目录：$repo_root"
  echo "将清理：$dist_dir"
  echo "将清理：$derived_data_dir"
  echo "将清理：$staging_dir"
  exit 0
fi

# 仅清理经过仓库边界校验的构建产物目录。
rm -rf -- "$dist_dir" "$derived_data_dir" "$staging_dir"
mkdir -p "$dist_dir" "$staging_dir"

cd -- "$repo_root"

"$script_dir/verify-xcode.sh"
xcodegen generate
xcodebuild \
  -project RoutinUsage.xcodeproj \
  -scheme RoutinUsage \
  -configuration Release \
  -derivedDataPath "$derived_data_dir" \
  CODE_SIGNING_ALLOWED=NO \
  clean build

ditto \
  "$derived_data_dir/Build/Products/Release/MyToken.app" \
  "$dist_dir/MyToken.app"

ditto "$dist_dir/MyToken.app" "$staging_dir/MyToken.app"
ditto "$repo_root/docs/首次运行说明.md" "$staging_dir/首次运行说明.md"

iconset_dir="$build_root/MyToken.iconset"
mkdir -p "$iconset_dir"
cp "$repo_root"/RoutinUsage/Assets.xcassets/AppIcon.appiconset/icon_*.png "$iconset_dir/"
iconutil -c icns \
  "$iconset_dir" \
  -o "$build_root/MyToken.icns"
cp "$build_root/MyToken.icns" "$staging_dir/.VolumeIcon.icns"
SetFile -a V "$staging_dir/.VolumeIcon.icns"

hdiutil create \
  -volname "MyToken" \
  -srcfolder "$staging_dir" \
  -ov \
  -format UDZO \
  "$dist_dir/MyToken.dmg"

rm -rf -- "$staging_dir"
