# Testing

## Test Suite

The `test_fetch.sh` script provides comprehensive testing for the Bookii/TING book downloader script without requiring an actual Bookii device.

### Running Tests

```bash
./test_fetch.sh
```

### What Gets Tested

The test suite validates:

1. **Script Validation**
   - Script exists and is executable
   - Shellcheck passes with no warnings
   - Help output is properly formatted

2. **API Availability**
   - Bookii Medienservice API (versions endpoint)
   - Bookii Medienservice API (medias endpoint)
   - TING backup server accessibility

3. **Metadata Parsing**
   - Python JSON parsing for Bookii API responses
   - Correct extraction of publisher ID, version, title, etc.
   - Version number lookup from versions API (not versionCount)

4. **Download URL Format**
   - Bookii KII URL format: `/{publisherId}/{mid}/{version}/{mid_5digit}_en.kii`
   - Bookii PNG URL format: `/{publisherId}/{mid}/{mid}_en.png`
   - TING description URL format
   - TING KII URL format
   - HTTP 200 responses for all URLs

5. **Script Functionality**
   - Handles Bookii books correctly
   - Falls back to TING server when needed
   - Validates mount paths
   - Handles invalid inputs gracefully

### Test Books

- **Bookii**: Book ID `9550` (Bibel «hör» memo - Schweizerdeutsch)
- **TING**: Book ID `5001` (Der Kinder Brockhaus Die Tiere)

### Requirements

- `bash` 3.2+
- `curl`
- `python3`
- `shellcheck` (optional, skipped if not installed)

### Exit Codes

- `0` - All tests passed
- `1` - One or more tests failed

### Example Output

```
========================================
Testing fetch_bookii_books.sh
========================================

Test directory: /tmp/tmp.xyz123

Running tests...

→ Test 1: Check script exists and is executable
✓ PASS: Script exists and is executable
→ Test 2: Check Bookii API availability
✓ PASS: Bookii versions API is accessible
✓ PASS: Bookii medias API is accessible
...

========================================
Test Summary
========================================
Passed: 14
Failed: 0

All tests passed!
```

### Adding New Tests

To add a new test:

1. Create a test function following the naming pattern `test_*`
2. Use helper functions:
   - `pass "message"` - Mark test as passed
   - `fail "message"` - Mark test as failed
   - `info "message"` - Print informational message
3. Add the test function call to the end of the script

Example:
```bash
test_my_feature() {
    info "Test: My feature description"
    
    if some_condition; then
        pass "Feature works as expected"
    else
        fail "Feature did not work"
        return 1
    fi
}
```

### CI/CD Integration

The test script can be integrated into CI/CD pipelines:

```yaml
# Example GitHub Actions
- name: Run tests
  run: ./test_fetch.sh
```

```bash
# Example pre-commit hook
#!/bin/bash
cd /path/to/ting
./test_fetch.sh || {
    echo "Tests failed, commit aborted"
    exit 1
}
```
