#!/usr/bin/env bash
#
# Bookii/TING Book Downloader
# Downloads book files for Bookii (or TING) digital reading pens.
#
# Sources:
#   1. Bookii Medienservice API (official, for all Bookii books)
#   2. TING backup server (legacy, for TING-compatible books)
#
# Usage: 
#   ./fetch_bookii_books.sh [MOUNT_PATH]              - Download books from tbd.txt
#   ./fetch_bookii_books.sh [MOUNT_PATH] BOOK_ID...   - Download specific book IDs
#
# Examples:
#   ./fetch_bookii_books.sh                           - Use default mount, read tbd.txt
#   ./fetch_bookii_books.sh "/Volumes/NO NAME"        - Specify mount path
#   ./fetch_bookii_books.sh "/Volumes/NO NAME" 5010 9660  - Download specific books
#
# Based on: https://www.reddit.com/r/de_EDV/comments/w2z1ea/

set -e

# Configuration
TING_SERVER_IP="13.80.138.170"
BOOKII_API_BASE="https://www.bookii-medienservice.de/Medienserver-1.0/api"
BOOKII_STREAMING_BASE="https://www.bookii-streamingservice.de/files"
DEFAULT_MOUNT_PATH="/Volumes/NO NAME"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Requires bash 4+ for associative arrays (unused but kept for potential future use)
# if [ "${BASH_VERSINFO[0]}" -ge 4 ]; then
#     declare -A BOOKII_METADATA_CACHE
# fi

show_help() {
    echo "Bookii/TING Book Downloader"
    echo ""
    echo "Usage:"
    echo "  $0 [MOUNT_PATH]              - Download books from tbd.txt"
    echo "  $0 [MOUNT_PATH] BOOK_ID...   - Download specific book IDs"
    echo ""
    echo "Arguments:"
    echo "  MOUNT_PATH    Path where Bookii is mounted (default: /Volumes/NO NAME)"
    echo "  BOOK_ID       One or more book IDs to download (e.g., 5010 9660)"
    echo ""
    echo "Examples:"
    echo "  $0                                    # Use defaults, read tbd.txt"
    echo "  $0 \"/Volumes/NO NAME\"                # Specify mount path"
    echo "  $0 \"/Volumes/NO NAME\" 5010 9660     # Download specific books"
    echo ""
    echo "Sources:"
    echo "  - Bookii Medienservice API: Native Bookii books (all IDs)"
    echo "  - TING backup server: Legacy TING books (IDs ~5000+)"
    exit 0
}

# Handle help flag
if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    show_help
fi

# Parse arguments
MOUNT_PATH="$DEFAULT_MOUNT_PATH"
MANUAL_BOOK_IDS=()

# First arg could be mount path or book ID
if [ $# -ge 1 ]; then
    if [ -d "$1" ]; then
        MOUNT_PATH="$1"
        shift
    elif [[ "$1" =~ ^[0-9]+$ ]]; then
        # First arg is a book ID, use default mount
        :
    else
        # First arg looks like a path but doesn't exist
        MOUNT_PATH="$1"
        shift
    fi
fi

# Remaining args are book IDs
while [ $# -gt 0 ]; do
    if [[ "$1" =~ ^[0-9]+$ ]]; then
        MANUAL_BOOK_IDS+=("$1")
    else
        echo -e "${YELLOW}Warning: Ignoring invalid book ID: $1${NC}"
    fi
    shift
done

# Paths on the device
BOOK_DIR="$MOUNT_PATH/book"
CONFIG_DIR="$MOUNT_PATH/configure"
TBD_FILE="$CONFIG_DIR/tbd.txt"

echo "========================================"
echo "Bookii/TING Book Downloader"
echo "========================================"
echo ""
echo -e "Mount path: ${BLUE}$MOUNT_PATH${NC}"
echo ""

# Check if mount path exists
if [ ! -d "$MOUNT_PATH" ]; then
    echo -e "${RED}Error: Mount path '$MOUNT_PATH' does not exist.${NC}"
    echo "Please connect your Bookii and ensure it's mounted."
    exit 1
fi

# Check if book directory exists
if [ ! -d "$BOOK_DIR" ]; then
    echo -e "${RED}Error: Book directory '$BOOK_DIR' does not exist.${NC}"
    echo "This doesn't look like a valid Bookii device."
    exit 1
fi

# Determine which book IDs to download
if [ ${#MANUAL_BOOK_IDS[@]} -gt 0 ]; then
    echo "Using manually specified book IDs..."
    BOOK_IDS=$(printf '%s\n' "${MANUAL_BOOK_IDS[@]}" | sort -u)
else
    # Check if tbd.txt exists
    if [ ! -f "$TBD_FILE" ]; then
        echo -e "${YELLOW}Warning: No tbd.txt found at '$TBD_FILE'.${NC}"
        echo "No books to download. Scan some books with your Bookii first,"
        echo "or specify book IDs manually."
        echo ""
        show_help
    fi

    echo "Reading pending books from tbd.txt..."
    
    # Extract valid book IDs (1-5 digit numbers)
    # Handle Windows line endings (CRLF) and strip null bytes/binary content
    BOOK_IDS=$(tr -d '\r\0' < "$TBD_FILE" | grep -aE '^[0-9]{1,5}$' 2>/dev/null | sort -u || true)
    
    if [ -z "$BOOK_IDS" ]; then
        echo -e "${YELLOW}No valid book IDs found in tbd.txt.${NC}"
        echo "Book IDs should be numeric (e.g., 5010 or 09660)."
        echo ""
        echo "Contents of tbd.txt:"
        cat "$TBD_FILE"
        exit 0
    fi
fi

echo ""
echo "Found book IDs to download:"
echo "$BOOK_IDS"
echo ""

# Note: fetch_bookii_metadata was removed as it's unused.
# The download_book_bookii function fetches metadata directly per book.

# Download book using Bookii Medienservice API
download_book_bookii() {
    local book_id_raw="$1"
    local area="en"  # Language area (en = international)
    
    local api_id=$((10#$book_id_raw))  # Remove leading zeros for API
    local file_id
    file_id=$(printf "%05d" "$api_id")  # Ensure 5-digit format for files
    
    # Get metadata from Bookii API
    echo -e "  ${CYAN}Checking Bookii API...${NC}"
    
    local mids_param="\"${api_id}\""
    local tmp_json="/tmp/bookii_response_$$.json"
    local tmp_versions="/tmp/bookii_versions_$$.json"
    
    # Fetch metadata
    if ! curl -sf "${BOOKII_API_BASE}/download/medias?mids=${mids_param}" -o "$tmp_json" 2>/dev/null; then
        echo -e "  ${YELLOW}Failed to fetch from Bookii API${NC}"
        rm -f "$tmp_json" "$tmp_versions"
        return 1
    fi
    
    # Check if response is empty array
    if [ "$(cat "$tmp_json")" = "[]" ]; then
        echo -e "  ${YELLOW}Book not found in Bookii API${NC}"
        rm -f "$tmp_json" "$tmp_versions"
        return 1
    fi
    
    # Fetch versions (needed for correct download path)
    # The versions API returns the CURRENT version number for each book
    # This is different from versionCount which is the total number of versions
    if ! curl -sf "${BOOKII_API_BASE}/download/versions/" -o "$tmp_versions" 2>/dev/null; then
        echo -e "  ${YELLOW}Failed to fetch versions from Bookii API${NC}"
        rm -f "$tmp_json" "$tmp_versions"
        return 1
    fi
    
    # Parse JSON response using Python, reading from files
    local metadata
    metadata=$(python3 -c "
import json
import sys

try:
    with open(sys.argv[1], 'r') as f:
        data = json.load(f)
    with open(sys.argv[2], 'r') as f:
        versions = json.load(f)
    if not data:
        sys.exit(1)
    item = data[0]
    mid = item.get('mid', '')
    title = item.get('title', '')
    author = item.get('author', '')
    publisher_id = item.get('publisher', {}).get('publisherId', '')
    # Get current version from versions API
    # Keys may be padded (e.g., '09550') or unpadded (e.g., '9550')
    mid_padded = str(mid).zfill(5)
    mid_unpadded = str(mid)
    version = versions.get(mid_padded) or versions.get(mid_unpadded) or 1
    print(f'{mid}|{publisher_id}|{version}|{title}|{author}')
except Exception as e:
    print(f'ERROR: {e}', file=sys.stderr)
    sys.exit(1)
" "$tmp_json" "$tmp_versions" 2>/dev/null)
    
    rm -f "$tmp_json" "$tmp_versions"
    
    if [ -z "$metadata" ]; then
        echo -e "  ${YELLOW}Failed to parse Bookii API response${NC}"
        return 1
    fi
    
    IFS='|' read -r _mid publisher_id version title author <<< "$metadata"
    
    if [ -z "$publisher_id" ] || [ -z "$version" ]; then
        echo -e "  ${YELLOW}Missing publisher or version info${NC}"
        return 1
    fi
    
    echo -e "  Book: ${BLUE}${title}${NC}"
    [ -n "$author" ] && echo -e "  Author: ${author}"
    echo -e "  Publisher ID: ${publisher_id}, Version: ${version}"
    
    local txt_file="$BOOK_DIR/${file_id}_${area}.txt"
    local png_file="$BOOK_DIR/${file_id}_${area}.png"
    local kii_file="$BOOK_DIR/${file_id}_${area}.kii"
    
    # Create description file from metadata
    echo "  Creating description file..."
    cat > "$txt_file" << EOF
Name: ${title}
Author: ${author}
Publisher: Tessloff/Bookii
Version: ${version}
EOF
    
    # Download thumbnail (PNG)
    echo "  Downloading thumbnail..."
    local png_url="${BOOKII_STREAMING_BASE}/${publisher_id}/${api_id}/${api_id}_${area}.png"
    if ! curl -sf "$png_url" -o "$png_file" 2>/dev/null; then
        echo -e "  ${YELLOW}Thumbnail not available (continuing anyway)${NC}"
        rm -f "$png_file"
    fi
    
    # Download book data (KII)
    echo "  Downloading book data (this may take a while)..."
    local kii_url="${BOOKII_STREAMING_BASE}/${publisher_id}/${api_id}/${version}/${file_id}_${area}.kii"
    if ! curl -f --progress-bar "$kii_url" -o "$kii_file" 2>/dev/null; then
        echo -e "  ${RED}Failed to download book data from Bookii streaming server${NC}"
        echo -e "  ${YELLOW}URL: ${kii_url}${NC}"
        rm -f "$txt_file" "$png_file" "$kii_file"
        return 1
    fi
    
    # Show file size
    local file_size
    file_size=$(du -h "$kii_file" 2>/dev/null | cut -f1)
    echo -e "  ${GREEN}Successfully downloaded book $file_id ($file_size) via Bookii API${NC}"
    return 0
}

# Download book using TING backup server (legacy fallback)
download_book_ting() {
    local book_id_raw="$1"
    local area="en"  # Language area (en = international)
    
    local api_id=$((10#$book_id_raw))  # Remove leading zeros for API
    local file_id
    file_id=$(printf "%05d" "$api_id")  # Ensure 5-digit format for files
    
    echo -e "  ${CYAN}Trying TING backup server...${NC}"
    
    local txt_file="$BOOK_DIR/${file_id}_${area}.txt"
    local png_file="$BOOK_DIR/${file_id}_${area}.png"
    local kii_file="$BOOK_DIR/${file_id}_${area}.kii"
    
    # Download description (txt) - API uses ID without leading zeros
    echo "  Downloading description..."
    if ! curl -sf "http://${TING_SERVER_IP}/book-files/get-description/id/${api_id}/area/${area}/" -o "$txt_file"; then
        echo -e "  ${RED}Failed to download description${NC}"
        rm -f "$txt_file"
        return 1
    fi
    
    # Check if we got a valid response (not "work not found")
    if grep -q "work not found" "$txt_file" 2>/dev/null; then
        echo -e "  ${RED}Book not found on TING server${NC}"
        rm -f "$txt_file"
        return 1
    fi
    
    # Show book name
    local book_name
    book_name=$(grep "^Name:" "$txt_file" 2>/dev/null | cut -d: -f2- | xargs)
    if [ -n "$book_name" ]; then
        echo -e "  Book: ${BLUE}$book_name${NC}"
    fi
    
    # Download thumbnail (png)
    echo "  Downloading thumbnail..."
    if ! curl -sf "http://${TING_SERVER_IP}/book-files/get/id/${api_id}/area/${area}/type/thumb/" -o "$png_file"; then
        echo -e "  ${YELLOW}Thumbnail not available (continuing anyway)${NC}"
        rm -f "$png_file"
    fi
    
    # Download book archive (ouf -> kii)
    echo "  Downloading book data (this may take a while)..."
    if ! curl -f --progress-bar "http://${TING_SERVER_IP}/book-files/get/id/${api_id}/area/${area}/type/archive/" -o "$kii_file"; then
        echo -e "  ${RED}Failed to download book data from TING server${NC}"
        rm -f "$txt_file" "$png_file" "$kii_file"
        return 1
    fi
    
    # Show file size
    local file_size
    file_size=$(du -h "$kii_file" 2>/dev/null | cut -f1)
    echo -e "  ${GREEN}Successfully downloaded book $file_id ($file_size) via TING server${NC}"
    return 0
}

# Download a single book - tries Bookii API first, then TING fallback
download_book() {
    local book_id_raw="$1"
    local area="en"
    
    local api_id=$((10#$book_id_raw))
    local file_id
    file_id=$(printf "%05d" "$api_id")
    
    echo -e "${YELLOW}Downloading book $file_id (ID: $api_id)...${NC}"
    
    # Check if book already exists
    if [ -f "$BOOK_DIR/${file_id}_${area}.kii" ]; then
        echo -e "  ${GREEN}Book already exists, skipping.${NC}"
        return 0
    fi
    
    # Try Bookii API first
    if download_book_bookii "$book_id_raw"; then
        return 0
    fi
    
    # Fallback to TING server
    if download_book_ting "$book_id_raw"; then
        return 0
    fi
    
    echo -e "  ${RED}Failed to download book $file_id from any source${NC}"
    return 1
}

# Download each book
SUCCESS_COUNT=0
FAIL_COUNT=0

for book_id in $BOOK_IDS; do
    if download_book "$book_id"; then
        ((SUCCESS_COUNT++)) || true
    else
        ((FAIL_COUNT++)) || true
    fi
    echo ""
done

# Clear the tbd.txt file if all downloads succeeded and we're using tbd.txt
if [ ${#MANUAL_BOOK_IDS[@]} -eq 0 ] && [ $FAIL_COUNT -eq 0 ] && [ $SUCCESS_COUNT -gt 0 ]; then
    echo "Clearing tbd.txt..."
    true > "$TBD_FILE"
fi

echo "========================================"
echo -e "${GREEN}Downloads complete!${NC}"
echo "  Successful: $SUCCESS_COUNT"
echo "  Failed: $FAIL_COUNT"
echo "========================================"

if [ $SUCCESS_COUNT -gt 0 ]; then
    echo ""
    echo "Please safely eject your Bookii before disconnecting."
    echo "On macOS: diskutil eject \"$MOUNT_PATH\""
fi

if [ $FAIL_COUNT -gt 0 ]; then
    echo ""
    echo -e "${YELLOW}Note: Some books failed to download.${NC}"
    echo "Possible reasons:"
    echo "  - Book ID doesn't exist in either Bookii API or TING archive"
    echo "  - Network connectivity issues"
    echo "  - Server temporarily unavailable"
fi
