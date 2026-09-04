#!/bin/bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
test_home="$(mktemp -d "${TMPDIR:-/tmp}/myroutin-tests.XXXXXX")"
test_derived_path="$repo_root/.build/test-derived"
test_app_path="$test_derived_path/Build/Products/Debug/MyToken.app"

cleanup_test_home() {
  if [[ -d "$test_home" ]]; then
    /bin/rm -rf "$test_home"
  fi
}

cleanup_test_preferences() {
  # cfprefsd 会在测试进程结束后延迟写回空的测试偏好文件，等待其完成后再删除。
  sleep 10
  find "$HOME/Library/Preferences" -maxdepth 1 -type f \
    \( -name 'ai.routin.usage-monitor.*-tests.*.plist' \
      -o -name 'AppSettingsTests.*.plist' \
      -o -name 'AppLifecycleTests.*.plist' \) \
    -delete
}

cleanup_test_host() {
  if pgrep -f "$test_app_path/Contents/MacOS/MyToken" >/dev/null; then
    pkill -f "$test_app_path/Contents/MacOS/MyToken" || true
  fi
}

trap cleanup_test_home EXIT

cd "$repo_root"
xcodegen generate
test_exit=0
CFFIXED_USER_HOME="$test_home" xcodebuild \
  -project RoutinUsage.xcodeproj \
  -scheme RoutinUsage \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath "$test_derived_path" \
  PRODUCT_BUNDLE_IDENTIFIER=ai.routin.mytoken.tests \
  CODE_SIGNING_ALLOWED=NO \
  test || test_exit=$?
cleanup_test_host
cleanup_test_preferences
exit "$test_exit"
