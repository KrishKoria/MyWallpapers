#!/bin/bash
set -e

# Define markers that indicate where thumbnails will be inserted.
START_MARKER="<!-- START THUMBNAILS -->"
END_MARKER="<!-- END THUMBNAILS -->"
README_FILE="README.md"

# Create thumbnails directory if it doesn't exist
THUMB_DIR=".thumbnails"
mkdir -p "$THUMB_DIR"

echo "Searching for image files..."
IMAGE_FILES_ARRAY=()
# Use find -print0 and process substitution with a while loop for robust filename handling
# Exclude .git, .thumbnails, and .github directories from the search
while IFS= read -r -d $'\0' file; do
  # Get a clean, relative path
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
echo "Found $TOTAL_FILES image files to process."

# Initialize thumbnails HTML - using table-based layout which works better in GitHub
THUMBNAILS_HTML="<table><tr>"
count=0
max_per_row=5
thumbnails_content_updated=false # Flag to track if any thumbnail HTML content changed

echo "Generating thumbnails and HTML..."
for file_path in "${SORTED_IMAGE_FILES[@]}"; do
    thumb_file_name=$(basename "$file_path")
    thumb_file_path="$THUMB_DIR/$thumb_file_name"

    # Create or update thumbnail if:
    # 1. Thumbnail doesn't exist
    # 2. Original file is newer than the thumbnail
    if [ ! -f "$thumb_file_path" ] || [ "$file_path" -nt "$thumb_file_path" ]; then
        echo "Creating/updating thumbnail for $file_path -> $thumb_file_path"
        if command -v convert &> /dev/null; then
            convert "$file_path" -resize 20% "$thumb_file_path" # Using 20% as an example, adjust as needed
        else
            echo "ImageMagick 'convert' not found. Copying original file as thumbnail."
            cp "$file_path" "$thumb_file_path"
        fi
        thumbnails_content_updated=true # A thumbnail was created/updated
    fi

    # Start a new row after every max_per_row images
    if [ $count -ne 0 ] && [ $(($count % $max_per_row)) -eq 0 ]; then
        THUMBNAILS_HTML+="</tr><tr>"
    fi

    THUMBNAILS_HTML+="<td align=\"center\">"
    # Use the thumbnail in the README but link to the original
    # Ensure paths are URL-encoded for HTML, though for simple relative paths it's often fine
    THUMBNAILS_HTML+="<a href=\"$file_path\"><img src=\"$thumb_file_path\" width=\"150\" height=\"150\" style=\"object-fit: cover;\" alt=\"$thumb_file_name\"/></a>"
    THUMBNAILS_HTML+="</td>"

    count=$((count + 1))
done

# Complete any remaining row and close the table
if [ $TOTAL_FILES -gt 0 ]; then
    # Fill remaining cells in the last row if it's not full
    remaining_cells=$((max_per_row - (count % max_per_row)))
    if [ $((count % max_per_row)) -ne 0 ]; then
        for ((i=0; i<remaining_cells; i++)); do
            THUMBNAILS_HTML+="<td></td>" # Empty cell
        done
    fi
    THUMBNAILS_HTML+="</tr></table>"
else
    THUMBNAILS_HTML="<p>No images found to display.</p>" # Or keep it as an empty table
fi


# Create new content to insert between markers.
NEW_THUMBNAIL_SECTION_CONTENT="$START_MARKER
$THUMBNAILS_HTML
$END_MARKER"

echo "Updating $README_FILE..."
readme_content_updated=false
if [ ! -f "$README_FILE" ]; then
    echo "Creating new $README_FILE."
    echo -e "# Wallpaper Collection\n\n$NEW_THUMBNAIL_SECTION_CONTENT" > "$README_FILE"
    readme_content_updated=true
else
    # Read current README content
    current_readme_content=$(cat "$README_FILE")
    # Extract current thumbnail section
    current_thumbnail_section=$(sed -n "/$START_MARKER/,/$END_MARKER/p" "$README_FILE")

    # If markers exist and the new content is different from current, or if thumbnails themselves were updated
    if grep -q "$START_MARKER" "$README_FILE" && grep -q "$END_MARKER" "$README_FILE"; then
        if [ "$current_thumbnail_section" != "$NEW_THUMBNAIL_SECTION_CONTENT" ] || [ "$thumbnails_content_updated" = true ]; then
            echo "Thumbnail section differs or thumbnails were updated. Updating $README_FILE."
            TEMP_FILE=$(mktemp)
            # Write content before START_MARKER
            sed "/$START_MARKER/Q" "$README_FILE" > "$TEMP_FILE"
            # Append new thumbnail section
            echo "$NEW_THUMBNAIL_SECTION_CONTENT" >> "$TEMP_FILE"
            # Append content after END_MARKER
            sed -n "/$END_MARKER/,\$p" "$README_FILE" | sed '1d' >> "$TEMP_FILE" # '1d' to remove the END_MARKER line itself from this part
            
            mv "$TEMP_FILE" "$README_FILE"
            readme_content_updated=true
        else
            echo "$README_FILE thumbnail section is already up-to-date."
        fi
    else
        echo "Markers not found in $README_FILE. Appending new thumbnail section."
        echo -e "\n$NEW_THUMBNAIL_SECTION_CONTENT" >> "$README_FILE"
        readme_content_updated=true
    fi
fi

if [ "$readme_content_updated" = true ] || [ "$thumbnails_content_updated" = true ]; then
    echo "Configuring Git..."
    git config --global user.email "action@github.com"
    git config --global user.name "GitHub Action"

    echo "Adding changes to Git..."
    git add "$README_FILE" "$THUMB_DIR" # Add specific files/dirs

    if [ -n "$(git status --porcelain)" ]; then
        echo "Changes detected by Git, committing..."
        git commit -m "Update image thumbnails in README [skip ci]"
        echo "Pushing changes..."
        git push "https://${GITHUB_ACTOR}:${GITHUB_TOKEN}@github.com/${GITHUB_REPOSITORY}.git" HEAD:${GITHUB_REF#refs/heads/}
        echo "Changes pushed successfully."
    else
        echo "No effective changes detected by Git to commit."
    fi
else
    echo "No updates made to README or thumbnails. Nothing to commit."
fi

echo "Script finished."