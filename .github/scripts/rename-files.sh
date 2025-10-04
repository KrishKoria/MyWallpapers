#!/bin/bash
set -euo pipefail

echo "=== File Renaming Script Started ==="
echo "Checking for files that need renaming..."

IMAGE_FILES_LIST=()
# Use find with extension-based detection (faster than file --mime-type)
while IFS= read -r -d $'\0' file; do
  IMAGE_FILES_LIST+=("$file")
done < <(find . -type f \( -iname "*.png" -o -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.bmp" \) \
  -not -path "./.git/*" \
  -not -path "./.thumbnails/*" \
  -not -path "./.github/*" \
  -print0)

# Sort the array of found image files using mapfile
mapfile -t sorted_image_files < <(printf '%s\n' "${IMAGE_FILES_LIST[@]}" | sort)

TOTAL_FILES=${#sorted_image_files[@]}
echo "✓ Found $TOTAL_FILES image files to process."

if [ "$TOTAL_FILES" -eq 0 ]; then
  echo "⚠ No image files found to rename."
  exit 0
fi

TEMP_DIR=$(mktemp -d)
echo "✓ Using temporary directory: $TEMP_DIR"

# Ensure cleanup on exit
trap 'rm -rf "$TEMP_DIR"' EXIT

COUNT=1
declare -A ORIGINAL_TO_TEMP_MAP

# First pass: Copy files to temp dir with new names
echo "=== Phase 1: Copying files to temporary directory ==="
for file in "${sorted_image_files[@]}"; do
  EXT="${file##*.}"
  # Normalize extension to lowercase
  EXT_LOWER=$(echo "$EXT" | tr '[:upper:]' '[:lower:]')
  NEW_NAME_IN_TEMP=$(printf "%03d.%s" "$COUNT" "$EXT_LOWER")
  
  if (( COUNT % 20 == 0 )) || (( COUNT == TOTAL_FILES )); then
    echo "  Progress: $COUNT/$TOTAL_FILES files processed..."
  fi
  
  cp "$file" "$TEMP_DIR/$NEW_NAME_IN_TEMP"
  ORIGINAL_TO_TEMP_MAP["$file"]="$TEMP_DIR/$NEW_NAME_IN_TEMP"
  
  COUNT=$((COUNT + 1))
done

# Second pass: Move files back with new names
echo "=== Phase 2: Renaming files to final names ==="
COUNT=1
ANY_FILE_RENAMED=false

for original_file_path in "${sorted_image_files[@]}"; do
  EXT="${original_file_path##*.}"
  EXT_LOWER=$(echo "$EXT" | tr '[:upper:]' '[:lower:]')
  FINAL_NEW_NAME=$(printf "%03d.%s" "$COUNT" "$EXT_LOWER")
  
  # Determine target directory (should be current directory for most cases)
  if [[ "$original_file_path" == ./* ]]; then
    TARGET_PATH="./$FINAL_NEW_NAME"
  else
    TARGET_PATH="$FINAL_NEW_NAME"
  fi
  
  TEMP_FILE_PATH=${ORIGINAL_TO_TEMP_MAP["$original_file_path"]}
  original_basename=$(basename "$original_file_path")
  
  # Check if renaming is needed
  if [ "$original_basename" != "$FINAL_NEW_NAME" ] || [ "$original_file_path" != "$TARGET_PATH" ]; then
    echo "  ✓ Renaming: $original_file_path -> $TARGET_PATH"
    mv "$TEMP_FILE_PATH" "$TARGET_PATH"
    
    # Remove original if it's different from target
    if [ "$original_file_path" != "$TARGET_PATH" ] && [ -f "$original_file_path" ]; then
      rm -f "$original_file_path"
    fi
    ANY_FILE_RENAMED=true
  else
    # File already has correct name, just move temp file back
    if [ -f "$TEMP_FILE_PATH" ]; then
      mv "$TEMP_FILE_PATH" "$TARGET_PATH"
    fi
  fi
  
  COUNT=$((COUNT + 1))
done

echo "=== Phase 3: Committing changes ==="

if [ "$ANY_FILE_RENAMED" = true ]; then
  git config --global user.email "action@github.com"
  git config --global user.name "GitHub Action"
  
  echo "✓ Files were renamed, committing changes..."
  git add -A
  
  if [ -n "$(git status --porcelain)" ]; then
    echo "✓ Changes detected by git, committing..."
    git commit -m "Rename files sequentially [skip ci]"
    
    # Only push if running in GitHub Actions
    if [ -n "${GITHUB_ACTOR:-}" ] && [ -n "${GITHUB_TOKEN:-}" ] && [ -n "${GITHUB_REPOSITORY:-}" ] && [ -n "${GITHUB_REF:-}" ]; then
      echo "✓ Pushing changes..."
      git push "https://${GITHUB_ACTOR}:${GITHUB_TOKEN}@github.com/${GITHUB_REPOSITORY}.git" HEAD:${GITHUB_REF#refs/heads/}
      echo "✓ Changes pushed successfully"
    else
      echo "⚠ Not running in GitHub Actions, skipping push."
    fi
  else
    echo "⚠ Git status clean after renaming, no commit needed."
  fi
else
  echo "✓ No files actually needed renaming."
fi

echo "=== File Renaming Script Completed ==="