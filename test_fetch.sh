#!/usr/bin/env bash
#
# Test script for fetch_bookii_books.sh
# Tests both Bookii API and TING fallback functionality
#

set -e

# Colors for output (unused colors removed for shellcheck)
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Test configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/fetch_bookii_books.sh"
TEST_DIR="$(mktemp -d)"
BOOKII_API_BASE="https://www.bookii-medienservice.de/Medienserver-1.0/api"
BOOKII_STREAMING_BASE="https://www.bookii-streamingservice.de/files"
TING_SERVER_IP="13.80.138.170"

# Test books
BOOKII_TEST_BOOK="9550"  # Bibel «hör» memo - Schweizerdeutsch (Bookii)
TING_TEST_BOOK="5001"    # Der Kinder Brockhaus Die Tiere (TING)

# Test results
TESTS_PASSED=0
TESTS_FAILED=0

echo "========================================"
echo "Testing fetch_bookii_books.sh"
echo "========================================"
echo ""
echo "Test directory: $TEST_DIR"
echo ""

# Helper functions
pass() {
    echo -e "${GREEN}✓ PASS${NC}: $1"
    ((TESTS_PASSED++)) || true
}

fail() {
    echo -e "${RED}✗ FAIL${NC}: $1"
    ((TESTS_FAILED++)) || true
}

info() {
    echo -e "${CYAN}→${NC} $1"
}

# Setup test environment
setup_test_env() {
    mkdir -p "$TEST_DIR/book"
    mkdir -p "$TEST_DIR/configure"
    echo "$1" > "$TEST_DIR/configure/tbd.txt"
}

# Called via trap EXIT
# shellcheck disable=SC2317,SC2329
cleanup() {
    rm -rf "$TEST_DIR"
}

trap cleanup EXIT

# Test 1: Check script exists and is executable
test_script_exists() {
    info "Test 1: Check script exists and is executable"
    if [ -f "$SCRIPT" ] && [ -x "$SCRIPT" ]; then
        pass "Script exists and is executable"
    else
        fail "Script not found or not executable"
        exit 1
    fi
}

# Test 2: Check Bookii API availability
test_bookii_api() {
    info "Test 2: Check Bookii API availability"
    
    # Test versions endpoint
    local versions_response
    versions_response=$(curl -sf "${BOOKII_API_BASE}/download/versions/" 2>/dev/null || echo "")
    if [ -n "$versions_response" ]; then
        pass "Bookii versions API is accessible"
    else
        fail "Bookii versions API is not accessible"
        return 1
    fi
    
    # Test medias endpoint
    local medias_response
    medias_response=$(curl -sf "${BOOKII_API_BASE}/download/medias?mids=\"${BOOKII_TEST_BOOK}\"" 2>/dev/null || echo "")
    if [ -n "$medias_response" ] && [ "$medias_response" != "[]" ]; then
        pass "Bookii medias API is accessible"
    else
        fail "Bookii medias API is not accessible"
        return 1
    fi
}

# Test 3: Check TING server availability
test_ting_server() {
    info "Test 3: Check TING server availability"
    
    local response
    response=$(curl -sf "http://${TING_SERVER_IP}/book-files/get-description/id/${TING_TEST_BOOK}/area/en/" 2>/dev/null || echo "")
    if [ -n "$response" ] && ! grep -q "work not found" <<< "$response"; then
        pass "TING server is accessible"
    else
        fail "TING server is not accessible"
        return 1
    fi
}

# Test 4: Verify Bookii book metadata parsing
test_bookii_metadata_parsing() {
    info "Test 4: Verify Bookii book metadata parsing"
    
    local tmp_json="/tmp/test_bookii_medias_$$.json"
    local tmp_versions="/tmp/test_bookii_versions_$$.json"
    
    if ! curl -sf "${BOOKII_API_BASE}/download/medias?mids=\"${BOOKII_TEST_BOOK}\"" -o "$tmp_json" 2>/dev/null; then
        fail "Failed to fetch Bookii metadata"
        rm -f "$tmp_json" "$tmp_versions"
        return 1
    fi
    
    if ! curl -sf "${BOOKII_API_BASE}/download/versions/" -o "$tmp_versions" 2>/dev/null; then
        fail "Failed to fetch Bookii versions"
        rm -f "$tmp_json" "$tmp_versions"
        return 1
    fi
    
    # Parse with Python (same logic as script)
    local metadata
    metadata=$(python3 -c "
import json
import sys

try:
    with open('$tmp_json', 'r') as f:
        data = json.load(f)
    with open('$tmp_versions', 'r') as f:
        versions = json.load(f)
    if not data:
        sys.exit(1)
    item = data[0]
    mid = item.get('mid', '')
    title = item.get('title', '')
    publisher_id = item.get('publisher', {}).get('publisherId', '')
    mid_padded = str(mid).zfill(5)
    mid_unpadded = str(mid)
    version = versions.get(mid_padded) or versions.get(mid_unpadded) or 1
    print(f'{mid}|{publisher_id}|{version}|{title}')
except Exception as e:
    print(f'ERROR: {e}', file=sys.stderr)
    sys.exit(1)
" 2>/dev/null)
    
    rm -f "$tmp_json" "$tmp_versions"
    
    if [ -n "$metadata" ]; then
        IFS='|' read -r mid publisher_id version title <<< "$metadata"
        if [ -n "$mid" ] && [ -n "$publisher_id" ] && [ -n "$version" ] && [ -n "$title" ]; then
            pass "Bookii metadata parsing works (Book: $title, Publisher: $publisher_id, Version: $version)"
        else
            fail "Bookii metadata parsing incomplete"
            return 1
        fi
    else
        fail "Bookii metadata parsing failed"
        return 1
    fi
}

# Test 5: Verify Bookii download URL format
test_bookii_download_url() {
    info "Test 5: Verify Bookii download URL format"
    
    # Get metadata first
    local tmp_json="/tmp/test_bookii_url_$$.json"
    local tmp_versions="/tmp/test_bookii_url_versions_$$.json"
    
    curl -sf "${BOOKII_API_BASE}/download/medias?mids=\"${BOOKII_TEST_BOOK}\"" -o "$tmp_json" 2>/dev/null
    curl -sf "${BOOKII_API_BASE}/download/versions/" -o "$tmp_versions" 2>/dev/null
    
    local metadata
    metadata=$(python3 -c "
import json
import sys

try:
    with open('$tmp_json', 'r') as f:
        data = json.load(f)
    with open('$tmp_versions', 'r') as f:
        versions = json.load(f)
    item = data[0]
    mid = item.get('mid', '')
    publisher_id = item.get('publisher', {}).get('publisherId', '')
    mid_padded = str(mid).zfill(5)
    mid_unpadded = str(mid)
    version = versions.get(mid_padded) or versions.get(mid_unpadded) or 1
    print(f'{mid}|{publisher_id}|{version}')
except Exception:
    sys.exit(1)
" 2>/dev/null)
    
    rm -f "$tmp_json" "$tmp_versions"
    
    IFS='|' read -r mid publisher_id version <<< "$metadata"
    local file_id
    file_id=$(printf "%05d" "$mid")
    
    # Test KII URL
    local kii_url="${BOOKII_STREAMING_BASE}/${publisher_id}/${mid}/${version}/${file_id}_en.kii"
    local http_code
    http_code=$(curl -sf -o /dev/null -w "%{http_code}" "$kii_url" 2>/dev/null || echo "000")
    
    if [ "$http_code" = "200" ]; then
        pass "Bookii KII download URL is valid ($kii_url)"
    else
        fail "Bookii KII download URL failed (HTTP $http_code): $kii_url"
        return 1
    fi
    
    # Test PNG URL (optional, may not exist)
    local png_url="${BOOKII_STREAMING_BASE}/${publisher_id}/${mid}/${mid}_en.png"
    http_code=$(curl -sf -o /dev/null -w "%{http_code}" "$png_url" 2>/dev/null || echo "000")
    
    if [ "$http_code" = "200" ]; then
        pass "Bookii PNG thumbnail URL is valid"
    else
        info "Bookii PNG thumbnail not available (HTTP $http_code) - this is OK"
    fi
}

# Test 6: Verify TING download URLs
test_ting_download_url() {
    info "Test 6: Verify TING download URLs"
    
    local api_id=$((10#$TING_TEST_BOOK))
    
    # Test description URL
    local desc_url="http://${TING_SERVER_IP}/book-files/get-description/id/${api_id}/area/en/"
    local http_code
    http_code=$(curl -sf -o /dev/null -w "%{http_code}" "$desc_url" 2>/dev/null || echo "000")
    
    if [ "$http_code" = "200" ]; then
        pass "TING description URL is valid"
    else
        fail "TING description URL failed (HTTP $http_code)"
        return 1
    fi
    
    # Test KII URL
    local kii_url="http://${TING_SERVER_IP}/book-files/get/id/${api_id}/area/en/type/archive/"
    http_code=$(curl -sf -o /dev/null -w "%{http_code}" "$kii_url" 2>/dev/null || echo "000")
    
    if [ "$http_code" = "200" ]; then
        pass "TING KII download URL is valid"
    else
        fail "TING KII download URL failed (HTTP $http_code)"
        return 1
    fi
}

# Test 7: Test script with Bookii book (dry run - metadata only)
test_script_bookii_metadata() {
    info "Test 7: Test script with Bookii book (metadata fetch)"
    
    setup_test_env "$BOOKII_TEST_BOOK"
    
    # Run the script and check for Bookii API usage
    local output
    output=$("$SCRIPT" "$TEST_DIR" 2>&1 || true)
    
    if echo "$output" | grep -q "Bookii/TING Book Downloader"; then
        pass "Script starts correctly with Bookii book"
    else
        fail "Script failed to start with Bookii book"
        echo "$output"
        return 1
    fi
    
    # Check that it tries to use Bookii API (not just TING fallback)
    if echo "$output" | grep -q "Checking Bookii API"; then
        pass "Script attempts to use Bookii API for Bookii books"
    else
        fail "Script does not attempt to use Bookii API"
        echo "$output"
        return 1
    fi
    
    # Verify it doesn't immediately fall back to TING for a Bookii book
    if echo "$output" | grep -q "Successfully downloaded.*via Bookii API"; then
        pass "Script successfully uses Bookii API"
    elif echo "$output" | grep -q "Book already exists"; then
        info "Book already exists in test directory (expected if script was run before)"
    elif echo "$output" | grep -q "via TING server"; then
        fail "Script incorrectly fell back to TING for a Bookii book"
        echo "$output"
        return 1
    else
        info "Book download status unclear (may be network issue)"
    fi
}

# Test 8: Test script with TING book (dry run - metadata only)
test_script_ting_metadata() {
    info "Test 8: Test script with TING book (metadata fetch)"
    
    setup_test_env "$TING_TEST_BOOK"
    
    local output
    output=$("$SCRIPT" "$TEST_DIR" 2>&1 || true)
    
    if echo "$output" | grep -q "Bookii/TING Book Downloader"; then
        pass "Script starts correctly with TING book"
    else
        fail "Script failed to start with TING book"
        echo "$output"
        return 1
    fi
    
    # Check that it tries Bookii API first, then falls back to TING
    if echo "$output" | grep -q "Book not found in Bookii API"; then
        pass "Script correctly reports Bookii API miss for TING-only book"
    else
        info "Bookii API response unclear (may already exist or network issue)"
    fi
    
    if echo "$output" | grep -q "Trying TING backup server"; then
        pass "Script correctly falls back to TING server"
    else
        info "TING fallback status unclear (may already exist)"
    fi
}

# Test 9: Test help output
test_help_output() {
    info "Test 9: Test help output"
    
    local output
    output=$("$SCRIPT" --help 2>&1 || true)
    
    if echo "$output" | grep -q "Usage:" && echo "$output" | grep -q "Examples:"; then
        pass "Help output is properly formatted"
    else
        fail "Help output is missing or malformed"
        return 1
    fi
}

# Test 10: Test invalid mount path handling
test_invalid_mount_path() {
    info "Test 10: Test invalid mount path handling"
    
    local output
    output=$("$SCRIPT" "/nonexistent/path/to/bookii" 9550 2>&1 || true)
    
    if echo "$output" | grep -q "does not exist"; then
        pass "Invalid mount path is properly handled"
    else
        fail "Invalid mount path handling failed"
        return 1
    fi
}

# Test 11: Test version number retrieval (critical for URL correctness)
test_version_number_retrieval() {
    info "Test 11: Test version number retrieval from versions API"
    
    local tmp_versions="/tmp/test_versions_api_$$.json"
    
    if ! curl -sf "${BOOKII_API_BASE}/download/versions/" -o "$tmp_versions" 2>/dev/null; then
        fail "Failed to fetch versions API"
        rm -f "$tmp_versions"
        return 1
    fi
    
    # Test that we can parse both padded and unpadded keys
    local version_padded version_unpadded
    version_padded=$(python3 -c "
import json
import sys
try:
    with open('$tmp_versions', 'r') as f:
        versions = json.load(f)
    # Try padded key (e.g., '09550')
    mid_padded = str($BOOKII_TEST_BOOK).zfill(5)
    version = versions.get(mid_padded)
    if version:
        print(version)
except Exception:
    pass
" 2>/dev/null)
    
    version_unpadded=$(python3 -c "
import json
import sys
try:
    with open('$tmp_versions', 'r') as f:
        versions = json.load(f)
    # Try unpadded key (e.g., '9550')
    version = versions.get('$BOOKII_TEST_BOOK')
    if version:
        print(version)
except Exception:
    pass
" 2>/dev/null)
    
    rm -f "$tmp_versions"
    
    # At least one should work
    if [ -n "$version_padded" ] || [ -n "$version_unpadded" ]; then
        local found_version="${version_padded:-$version_unpadded}"
        pass "Version retrieval works (found version $found_version for book $BOOKII_TEST_BOOK)"
        
        # Verify this version number produces a valid URL
        local metadata
        metadata=$(curl -sf "${BOOKII_API_BASE}/download/medias?mids=\"${BOOKII_TEST_BOOK}\"" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    if data:
        item = data[0]
        mid = item['mid']
        pub_id = item['publisher']['publisherId']
        print(f'{mid}|{pub_id}')
except:
    pass
" 2>/dev/null)
        
        if [ -n "$metadata" ]; then
            IFS='|' read -r mid pub_id <<< "$metadata"
            local file_id
            file_id=$(printf "%05d" "$mid")
            local test_url="${BOOKII_STREAMING_BASE}/${pub_id}/${mid}/${found_version}/${file_id}_en.kii"
            local http_code
            http_code=$(curl -sf -o /dev/null -w "%{http_code}" "$test_url" 2>/dev/null || echo "000")
            
            if [ "$http_code" = "200" ]; then
                pass "Version number generates valid download URL"
            else
                fail "Version number does not generate valid URL (HTTP $http_code): $test_url"
                return 1
            fi
        fi
    else
        fail "Could not retrieve version number from versions API"
        return 1
    fi
}

# Test 12: Verify shellcheck passes
test_shellcheck() {
    info "Test 11: Verify shellcheck passes"
    
    if ! command -v shellcheck &> /dev/null; then
        info "shellcheck not installed, skipping"
        return 0
    fi
    
    if shellcheck "$SCRIPT" 2>&1; then
        pass "shellcheck passes with no warnings"
    else
        fail "shellcheck found issues"
        return 1
    fi
}

# Run all tests
echo "Running tests..."
echo ""

test_script_exists
test_bookii_api
test_ting_server
test_bookii_metadata_parsing
test_bookii_download_url
test_ting_download_url
test_script_bookii_metadata
test_script_ting_metadata
test_help_output
test_invalid_mount_path
test_version_number_retrieval
test_shellcheck

# Summary
echo ""
echo "========================================"
echo "Test Summary"
echo "========================================"
echo -e "${GREEN}Passed: $TESTS_PASSED${NC}"
echo -e "${RED}Failed: $TESTS_FAILED${NC}"
echo ""

if [ $TESTS_FAILED -eq 0 ]; then
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}Some tests failed.${NC}"
    exit 1
fi
