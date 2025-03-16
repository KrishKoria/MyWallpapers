#!/bin/bash
# filepath: c:\Imp things BAcking Up\wallpapers\.github\scripts\rename-files.sh
set -e

echo "Checking for files that need renaming..."

# Find all potential image files based on extension
IMAGE_FILES_TEMP=$(find . -type f \( -iname "*.png" -o -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.bmp" \) -not -path "./.git/*" -not -path "./.thumbnails/*" -not -path "./.github/*" | sort)

# Filter to ensure we only have actual image files
IMAGE_FILES=""
while IFS= read -r file; do
  # Skip if empty line
  [ -z "$file" ] && continue
  
  # Use file command to check if it's actually an image
  if file --mime-type "$file" | grep -q "image/"; then
    # Append file to our list with a newline
    IMAGE_FILES="${IMAGE_FILES}${file}"$'\n'
    echo "Found image: $file"
  else
    echo "Skipping non-image file: $file"
  fi
done <<< "$IMAGE_FILES_TEMP"

# Count how many files we have
TOTAL_FILES=$(echo -n "$IMAGE_FILES" | grep -c .)
echo "Found $TOTAL_FILES image files"

# Create a temporary directory for the renaming process
TEMP_DIR=$(mktemp -d)
echo "Using temporary directory: $TEMP_DIR"

# Counter for sequential numbering
COUNT=1

# First, copy files to temp dir with new names
while IFS= read -r file; do
  # Skip if empty line
  [ -z "$file" ] && continue
  
  # Get file extension
  EXT="${file##*.}"
  
  # Format number with leading zeros (001, 002, etc.)
  NEW_NAME=$(printf "%03d.%s" "$COUNT" "$EXT")
  
  echo "Processing: $file -> $NEW_NAME"
  cp "$file" "$TEMP_DIR/$NEW_NAME"
  
  COUNT=$((COUNT + 1))
done <<< "$IMAGE_FILES"

# Now move files back with new names, but only if they're different
COUNT=1
while IFS= read -r file; do
  # Skip if empty line
  [ -z "$file" ] && continue
  
  # Get file extension
  EXT="${file##*.}"
  
  # Format number with leading zeros
  NEW_NAME=$(printf "%03d.%s" "$COUNT" "$EXT")
  
  # Only rename if the names are different
  BASENAME=$(basename "$file")
  if [ "$BASENAME" != "$NEW_NAME" ]; then
    echo "Renaming: $file -> $NEW_NAME"
    mv "$TEMP_DIR/$NEW_NAME" "${file%/*}/$NEW_NAME"
    rm -f "$file"
  else
    echo "File already has correct name: $file"
  fi
  
  COUNT=$((COUNT + 1))
done <<< "$IMAGE_FILES"

# Clean up temp directory
rm -rf "$TEMP_DIR"
echo "File renaming complete!"

# # Configure Git for potential commits
# git config --global user.email "action@github.com"
# git config --global user.name "GitHub Action"

# # Check if we have any changes to commit
# echo "Files were renamed, committing changes..."
# git add -A
# if [ -n "$(git status --porcelain)" ]; then
#     echo "Changes detected, committing..."
#     git commit -m "Rename files sequentially [skip ci]"
    
#     # Use the GITHUB_TOKEN for authentication
#     git push "https://${GITHUB_ACTOR}:${GITHUB_TOKEN}@github.com/${GITHUB_REPOSITORY}.git" HEAD:${GITHUB_REF#refs/heads/}
#     echo "Changes pushed successfully"
# else
#     echo "No changes to commit"
# fi