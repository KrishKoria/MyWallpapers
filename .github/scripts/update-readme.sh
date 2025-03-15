#!/bin/bash
set -e

# Define markers that indicate where thumbnails will be inserted.
START_MARKER="<!-- START THUMBNAILS -->"
END_MARKER="<!-- END THUMBNAILS -->"

# Find all image files (adjust extensions as needed)
# This command lists images, strips the leading "./", and sorts them.
IMAGE_FILES=$(find . -type f \( -iname "*.png" -o -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.bmp" \) -not -path "./.git/*" -exec realpath --relative-to=. {} \; | sort)

# Build the thumbnails markdown/HTML snippet.
# Here we use HTML img tags with a fixed width for thumbnails.
THUMBNAILS=""
while IFS= read -r file; do
    THUMBNAILS+="<img src=\"$file\" width=\"150\" style=\"margin:5px;\" />"$'\n'
done <<< "$IMAGE_FILES"

# Create new content to insert between markers.
NEW_SECTION="$START_MARKER
$THUMBNAILS
$END_MARKER"

# Update README.md using a temporary file approach
if grep -q "$START_MARKER" README.md && grep -q "$END_MARKER" README.md; then
    # Create a temporary file
    TEMP_FILE=$(mktemp)
    
    # Extract the part before START_MARKER
    sed -n "1,/$START_MARKER/p" README.md | sed '$d' > "$TEMP_FILE"
    
    # Append our new section
    echo "$NEW_SECTION" >> "$TEMP_FILE"
    
    # Extract the part after END_MARKER
    sed -n "/$END_MARKER/,\$p" README.md | sed '1d' >> "$TEMP_FILE"
    
    # Replace the original file
    mv "$TEMP_FILE" README.md
else
    # If the markers don't exist, append the new section to the README.
    echo -e "\n$NEW_SECTION" >> README.md
fi

# Configure Git.
git config --global user.email "action@github.com"
git config --global user.name "GitHub Action"

# If README.md was modified, commit and push the changes.
if [ -n "$(git status --porcelain)" ]; then
    git add README.md
    git commit -m "Update image thumbnails in README [skip ci]"
    git push
else
    echo "No changes to README.md"
fi