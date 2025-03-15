#!/bin/bash
set -e

# Define markers that indicate where thumbnails will be inserted.
START_MARKER="<!-- START THUMBNAILS -->"
END_MARKER="<!-- END THUMBNAILS -->"

# Find all image files (adjust extensions as needed)
# This command lists images, strips the leading "./", and sorts them.
IMAGE_FILES=$(find . -type f \( -iname "*.png" -o -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.gif" \) -not -path "./.git/*" -exec realpath --relative-to=. {} \; | sort)

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

# Update README.md.
# If the markers exist, replace the content between them.
if grep -q "$START_MARKER" README.md && grep -q "$END_MARKER" README.md; then
    # Using sed to replace from START_MARKER to END_MARKER.
    # The command below works on Linux; on macOS you may need to adjust the sed -i flag.
    sed -i.bak "/$START_MARKER/,/$END_MARKER/c\\
$NEW_SECTION
" README.md
    rm README.md.bak
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
