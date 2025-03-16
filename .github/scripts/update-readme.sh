#!/bin/bash
set -e

# Define markers that indicate where thumbnails will be inserted.
START_MARKER="<!-- START THUMBNAILS -->"
END_MARKER="<!-- END THUMBNAILS -->"

# Create thumbnails directory if it doesn't exist
THUMB_DIR=".thumbnails"
mkdir -p "$THUMB_DIR"

# Find all image files (adjust extensions as needed)
# This command lists images, strips the leading "./", and sorts them.
IMAGE_FILES=$(find . -type f \( -iname "*.png" -o -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.bmp" \) -not -path "./.git/*" -not -path "./$THUMB_DIR/*" -exec realpath --relative-to=. {} \; | sort)

# Initialize thumbnails HTML - using table-based layout which works better in GitHub
THUMBNAILS="<table><tr>"
count=0
max_per_row=5

# Track if any thumbnails were actually created/updated
THUMBNAILS_UPDATED=false

# Add each image to the grid using a table layout
while IFS= read -r file; do
    # Create a thumbnail version if it doesn't exist
    thumb_file="$THUMB_DIR/$(basename "$file")"
    if [ ! -f "$thumb_file" ] || [ "$file" -nt "$thumb_file" ]; then
        echo "Creating thumbnail for $file"
        # Check if ImageMagick is available
        if command -v convert &> /dev/null; then
            # Create thumbnail using ImageMagick (10% size)
            convert "$file" -resize 10% "$thumb_file"
        else
            # If ImageMagick isn't available, just copy the original
            cp "$file" "$thumb_file"
        fi
        THUMBNAILS_UPDATED=true
    fi
    
    # Start a new row after every 5 images
    if [ $count -ne 0 ] && [ $(($count % $max_per_row)) -eq 0 ]; then
        THUMBNAILS+="</tr><tr>"
    fi
    
    THUMBNAILS+="<td align=\"center\">"
    # Use the thumbnail in the README but link to the original
    THUMBNAILS+="<a href=\"$file\"><img src=\"$thumb_file\" width=\"150\" height=\"150\" style=\"object-fit: cover;\"/></a>"
    THUMBNAILS+="</td>"
    
    count=$((count + 1))
done <<< "$IMAGE_FILES"

# Complete any remaining row and close the table
THUMBNAILS+="</tr></table>"

# Create new content to insert between markers.
NEW_SECTION="$START_MARKER
$THUMBNAILS
$END_MARKER"

# Update README.md if needed
README_UPDATED=false
if [ ! -f "README.md" ]; then
    echo "Creating new README.md"
    echo -e "# Wallpaper Collection\n\n$NEW_SECTION" > README.md
    README_UPDATED=true
elif grep -q "$START_MARKER" README.md && grep -q "$END_MARKER" README.md; then
    # Create a temporary file
    TEMP_FILE=$(mktemp)
    
    # Extract the part before START_MARKER
    sed -n "1,/$START_MARKER/p" README.md | sed '$d' > "$TEMP_FILE"
    
    # Append our new section
    echo "$NEW_SECTION" >> "$TEMP_FILE"
    
    # Extract the part after END_MARKER
    sed -n "/$END_MARKER/,\$p" README.md | sed '1d' >> "$TEMP_FILE"
    
    # Check if there's a difference before replacing
    if ! cmp -s "$TEMP_FILE" README.md; then
        echo "Updating existing README.md"
        mv "$TEMP_FILE" README.md
        README_UPDATED=true
    else
        echo "No changes needed to README.md"
        rm "$TEMP_FILE"
    fi
else
    # If the markers don't exist, append the new section to the README.
    echo "Adding thumbnail section to existing README.md"
    echo -e "\n$NEW_SECTION" >> README.md
    README_UPDATED=true
fi

# Configure Git
git config --global user.email "action@github.com"
git config --global user.name "GitHub Action"

# Check if we have any changes to commit
git add -A
if [ -n "$(git status --porcelain)" ]; then
    echo "Changes detected, committing..."
    git commit -m "Update image thumbnails in README [skip ci]"
    
    # Use the GITHUB_TOKEN for authentication
    git push "https://${GITHUB_ACTOR}:${GITHUB_TOKEN}@github.com/${GITHUB_REPOSITORY}.git" HEAD:${GITHUB_REF#refs/heads/}
    echo "Changes pushed successfully"
else
    echo "No changes to commit"
fi