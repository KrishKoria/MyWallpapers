#!/bin/bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SCRIPT_PATH="$ROOT_DIR/.github/scripts/update-readme.sh"
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

assert_file_content() {
  local file_path=$1
  local expected=$2
  local actual

  actual=$(cat "$file_path")

  if [[ "$actual" != "$expected" ]]; then
    echo "Assertion failed for $file_path"
    echo "Expected: $expected"
    echo "Actual:   $actual"
    exit 1
  fi
}

cat > "$TEST_DIR/README.md" <<'EOF'
# Test README

<!-- START THUMBNAILS -->
<p>placeholder</p>
<!-- END THUMBNAILS -->
EOF

printf 'old-image' > "$TEST_DIR/001.jpg"

(
  cd "$TEST_DIR"
  git init >/dev/null
  git config user.email test@example.com
  git config user.name "Test Runner"
  git add README.md 001.jpg
  git commit -m "Initial test state" >/dev/null
)

(
  cd "$TEST_DIR"
  bash "$SCRIPT_PATH" >/dev/null
)

assert_file_content "$TEST_DIR/.thumbnails/001.jpg" "old-image"

# Simulate a later workflow restore where the cached thumbnail is newer than the
# checked-out source file, but the numbered source file now points at different content.
printf 'new-image' > "$TEST_DIR/001.jpg"
touch -t 202401010101 "$TEST_DIR/001.jpg"
touch -t 202401010102 "$TEST_DIR/.thumbnails/001.jpg"

(
  cd "$TEST_DIR"
  bash "$SCRIPT_PATH" >/dev/null
)

assert_file_content "$TEST_DIR/.thumbnails/001.jpg" "new-image"

echo "update-readme regression test passed"
