#!/bin/bash
set -euo pipefail

# Configuration
START_MARKER="<!-- START THUMBNAILS -->"
END_MARKER="<!-- END THUMBNAILS -->"
README_FILE="README.md"
THUMB_DIR=".thumbnails"
MAX_PER_ROW=5
THUMB_SIZE="150x150^"  # ^ forces exact dimensions with cropping
THUMB_QUALITY=85       # JPEG quality (1-100)

echo "=== README Update Script Started ==="

# Create thumbnails directory if it doesn't exist
mkdir -p "$THUMB_DIR"

echo "=== Phase 1: Discovering image files ==="
IMAGE_FILES_ARRAY=()
while IFS= read -r -d $'\0' file; do
  relative_file_path=$(realpath --relative-to=. "$file")
  IMAGE_FILES_ARRAY+=("$relative_file_path")
done < <(find . -type f \( -iname "*.png" -o -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.bmp" \) \
            -not -path "./.git/*" \
            -not -path "./$THUMB_DIR/*" \
            -not -path "./.github/*" \
            -print0)

# Sort the array of found image files
IFS=$'\n' SORTED_IMAGE_FILES=($(sort <<<"${IMAGE_FILES_ARRAY[*]}"))
unset IFS

TOTAL_FILES=${#SORTED_IMAGE_FILES[@]}
echo "✓ Found $TOTAL_FILES image files to process."

if [ "$TOTAL_FILES" -eq 0 ]; then
  echo "⚠ No image files found."
  THUMBNAILS_HTML="<p>No images found to display.</p>"
else
  echo "=== Phase 2: Generating thumbnails ==="
  
  thumbnails_content_updated=false
  processed=0
  
  # Function to generate a single thumbnail (for parallel execution)
  generate_thumbnail() {
    local file_path=$1
    local thumb_file_name=$(basename "$file_path")
    local thumb_file_path="$THUMB_DIR/$thumb_file_name"
    
    # Create or update thumbnail if needed
    if [ ! -f "$thumb_file_path" ] || [ "$file_path" -nt "$thumb_file_path" ]; then
      # Use optimized ImageMagick settings for better performance
      if ! convert "$file_path" \
        -auto-orient \
        -thumbnail "$THUMB_SIZE" \
        -gravity center \
        -extent "$THUMB_SIZE" \
        -quality "$THUMB_QUALITY" \
        -strip \
        "$thumb_file_path" 2>/dev/null; then
        echo "  ⚠ Warning: Failed to create thumbnail for $file_path, using original"
        cp "$file_path" "$thumb_file_path" 2>/dev/null || true
      fi
      return 0  # Indicates thumbnail was updated
    fi
    return 1  # Indicates no update needed
  }
  
  # Export function for parallel execution
  export -f generate_thumbnail
  export THUMB_DIR THUMB_SIZE THUMB_QUALITY
  
  # Process thumbnails with parallel jobs (up to 4 at a time)
  # Check if GNU parallel is available, otherwise use sequential processing
  if command -v parallel &> /dev/null; then
    echo "✓ Using GNU parallel for faster processing..."
    printf '%s\n' "${SORTED_IMAGE_FILES[@]}" | \
      parallel -j 4 --will-cite generate_thumbnail {} && thumbnails_content_updated=true || true
  else
    # Sequential processing with progress indicator
    for file_path in "${SORTED_IMAGE_FILES[@]}"; do
      if generate_thumbnail "$file_path"; then
        thumbnails_content_updated=true
      fi
      
      processed=$((processed + 1))
      if (( processed % 20 == 0 )) || (( processed == TOTAL_FILES )); then
        echo "  Progress: $processed/$TOTAL_FILES thumbnails processed..."
      fi
    done
  fi
  
  echo "✓ Thumbnail generation complete."
  
  echo "=== Phase 3: Building HTML gallery ==="
  
  # Build HTML table
  THUMBNAILS_HTML="<table><tr>"
  count=0
  
  for file_path in "${SORTED_IMAGE_FILES[@]}"; do
    thumb_file_name=$(basename "$file_path")
    thumb_file_path="$THUMB_DIR/$thumb_file_name"
    
    # Start a new row after every MAX_PER_ROW images
    if [ $count -ne 0 ] && [ $(($count % MAX_PER_ROW)) -eq 0 ]; then
      THUMBNAILS_HTML+="</tr><tr>"
    fi
    
    THUMBNAILS_HTML+="<td align=\"center\">"
    THUMBNAILS_HTML+="<a href=\"$file_path\"><img src=\"$thumb_file_path\" width=\"150\" height=\"150\" style=\"object-fit: cover;\" alt=\"$thumb_file_name\"/></a>"
    THUMBNAILS_HTML+="</td>"
    
    count=$((count + 1))
  done
  
  # Fill remaining cells in the last row
  remaining_cells=$((MAX_PER_ROW - (count % MAX_PER_ROW)))
  if [ $((count % MAX_PER_ROW)) -ne 0 ]; then
    for ((i=0; i<remaining_cells; i++)); do
      THUMBNAILS_HTML+="<td></td>"
    done
  fi
  
  THUMBNAILS_HTML+="</tr></table>"
  echo "✓ HTML gallery built with $count images."
fi

# Create new content to insert between markers
NEW_THUMBNAIL_SECTION_CONTENT="$START_MARKER
$THUMBNAILS_HTML
$END_MARKER"

echo "=== Phase 4: Updating $README_FILE ==="
readme_content_updated=false

if [ ! -f "$README_FILE" ]; then
  echo "✓ Creating new $README_FILE."
  echo -e "# Wallpaper Collection\n\n$NEW_THUMBNAIL_SECTION_CONTENT" > "$README_FILE"
  readme_content_updated=true
else
  # Check if markers exist
  if grep -q "$START_MARKER" "$README_FILE" && grep -q "$END_MARKER" "$README_FILE"; then
    # Extract current thumbnail section
    current_thumbnail_section=$(sed -n "/$START_MARKER/,/$END_MARKER/p" "$README_FILE")
    
    # Update if content changed or thumbnails were updated
    if [ "$current_thumbnail_section" != "$NEW_THUMBNAIL_SECTION_CONTENT" ] || [ "$thumbnails_content_updated" = true ]; then
      echo "✓ Updating thumbnail section in $README_FILE."
      TEMP_FILE=$(mktemp)
      
      # Write content before START_MARKER
      sed "/$START_MARKER/Q" "$README_FILE" > "$TEMP_FILE"
      # Append new thumbnail section
      echo "$NEW_THUMBNAIL_SECTION_CONTENT" >> "$TEMP_FILE"
      # Append content after END_MARKER (excluding END_MARKER itself)
      sed -n "/$END_MARKER/,\$p" "$README_FILE" | sed '1d' >> "$TEMP_FILE"
      
      mv "$TEMP_FILE" "$README_FILE"
      readme_content_updated=true
    else
      echo "✓ $README_FILE thumbnail section is already up-to-date."
    fi
  else
    echo "⚠ Markers not found in $README_FILE. Appending new thumbnail section."
    echo -e "\n$NEW_THUMBNAIL_SECTION_CONTENT" >> "$README_FILE"
    readme_content_updated=true
  fi
fi

echo "=== Phase 5: Committing changes ==="

if [ "$readme_content_updated" = true ] || [ "$thumbnails_content_updated" = true ]; then
  echo "✓ Configuring Git..."
  git config --global user.email "action@github.com"
  git config --global user.name "GitHub Action"

  echo "✓ Adding changes to Git..."
  git add "$README_FILE" "$THUMB_DIR"

  if [ -n "$(git status --porcelain)" ]; then
    echo "✓ Changes detected by Git, committing..."
    git commit -m "Update image thumbnails in README [skip ci]"
    echo "✓ Pushing changes..."
    git push "https://${GITHUB_ACTOR}:${GITHUB_TOKEN}@github.com/${GITHUB_REPOSITORY}.git" HEAD:${GITHUB_REF#refs/heads/}
    echo "✓ Changes pushed successfully."
  else
    echo "⚠ No effective changes detected by Git to commit."
  fi
else
  echo "✓ No updates made to README or thumbnails. Nothing to commit."
fi

echo "=== README Update Script Completed ==="