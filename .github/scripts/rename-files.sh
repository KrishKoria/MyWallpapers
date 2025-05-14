#!/bin/bash
set -e

echo "Checking for files that need renaming..."

IMAGE_FILES_LIST=()
# Use find -print0 and process substitution with a while loop for robust filename handling
while IFS= read -r -d $'\0' file; do
  if file --mime-type "$file" | grep -q "image/"; then
    IMAGE_FILES_LIST+=("$file")
    echo "Found image: $file"
  else
    echo "Skipping non-image file: $file"
  fi
done < <(find . -type f \( -iname "*.png" -o -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.bmp" \) -not -path "./.git/*" -not -path "./.thumbnails/*" -not -path "./.github/*" -print0)

# Sort the array of found image files
IFS=$'\n' sorted_image_files=($(sort <<<"${IMAGE_FILES_LIST[*]}"))
unset IFS

TOTAL_FILES=${#sorted_image_files[@]}
echo "Found $TOTAL_FILES image files to process."

if [ "$TOTAL_FILES" -eq 0 ]; then
  echo "No image files found to rename."
  exit 0
fi

TEMP_DIR=$(mktemp -d)
echo "Using temporary directory: $TEMP_DIR"

COUNT=1
declare -A ORIGINAL_TO_TEMP_MAP # Keep track of original files copied to temp

# First, copy files to temp dir with new names
for file in "${sorted_image_files[@]}"; do
  EXT="${file##*.}"
  NEW_NAME_IN_TEMP=$(printf "%03d.%s" "$COUNT" "$EXT")
  
  echo "Copying to temp: $file -> $TEMP_DIR/$NEW_NAME_IN_TEMP"
  cp "$file" "$TEMP_DIR/$NEW_NAME_IN_TEMP"
  ORIGINAL_TO_TEMP_MAP["$file"]="$TEMP_DIR/$NEW_NAME_IN_TEMP"
  
  COUNT=$((COUNT + 1))
done

# Now move files back with new names, but only if they're different
COUNT=1
ANY_FILE_RENAMED=false
for original_file_path in "${sorted_image_files[@]}"; do
  EXT="${original_file_path##*.}"
  FINAL_NEW_NAME=$(printf "%03d.%s" "$COUNT" "$EXT")
  TARGET_PATH="${original_file_path%/*}/$FINAL_NEW_NAME" # New name in original directory
  
  TEMP_FILE_PATH=${ORIGINAL_TO_TEMP_MAP["$original_file_path"]}
  
  original_basename=$(basename "$original_file_path")
  
  if [ "$original_basename" != "$FINAL_NEW_NAME" ] || [ "$original_file_path" != "$TARGET_PATH" ]; then
    echo "Renaming: $original_file_path -> $TARGET_PATH"
    mv "$TEMP_FILE_PATH" "$TARGET_PATH"
    # Only remove original if it's not the same as target (e.g. case change on case-insensitive fs)
    if [ "$original_file_path" != "$TARGET_PATH" ]; then
        rm -f "$original_file_path"
    fi
    ANY_FILE_RENAMED=true
  else
    echo "File already has correct name and location: $original_file_path"
    # If no rename needed, but content might have changed (unlikely for this script's purpose)
    # For safety, ensure the temp file is moved back if it was the same name
    if [ -f "$TEMP_FILE_PATH" ]; then # Check if temp file exists
        mv "$TEMP_FILE_PATH" "$TARGET_PATH" # Ensure it's back
    fi
  fi
  
  COUNT=$((COUNT + 1))
done

rm -rf "$TEMP_DIR"
echo "File renaming complete!"

if [ "$ANY_FILE_RENAMED" = true ]; then
  git config --global user.email "action@github.com"
  git config --global user.name "GitHub Action"
  echo "Files were renamed, committing changes..."
  git add -A
  if [ -n "$(git status --porcelain)" ]; then
      echo "Changes detected by git, committing..."
      git commit -m "Rename files sequentially [skip ci]"
      git push "https://${GITHUB_ACTOR}:${GITHUB_TOKEN}@github.com/${GITHUB_REPOSITORY}.git" HEAD:${GITHUB_REF#refs/heads/}
      echo "Changes pushed successfully"
  else
      echo "Git status clean after renaming, no commit needed."
  fi
else
  echo "No files actually needed renaming."
fi