# Bookii/TING Book Downloader

[![Tests](https://github.com/t2d/bookii-downloader/workflows/Tests/badge.svg)](https://github.com/t2d/bookii-downloader/actions)

Download book files for **Bookii** and **TING** digital reading pens without the proprietary Windows/Mac software.

## Features

- ✨ **Multi-source**: Downloads from both Bookii API and legacy TING servers
- 🔄 **Auto-fallback**: Tries Bookii API first, falls back to TING if needed
- 📱 **No software required**: Direct download via bash script
- 🧪 **Well-tested**: 20 automated tests ensure reliability
- 🚀 **Fast**: Downloads books in parallel when possible
- 💻 **Cross-platform**: Works on macOS and Linux

## Quick Start

```bash
# 1. Connect your Bookii pen to your computer
# 2. Scan some books with your Bookii pen (creates tbd.txt)
# 3. Run the script
./fetch_bookii_books.sh
```

The script will automatically:
- Read pending book IDs from `tbd.txt`
- Download book data (.kii), thumbnails (.png), and metadata (.txt)
- Clear `tbd.txt` when complete

## Usage

### Download books from tbd.txt

```bash
./fetch_bookii_books.sh "/Volumes/NO NAME"
```

### Download specific books

```bash
./fetch_bookii_books.sh "/Volumes/NO NAME" 9550 5010
```

### Custom mount path

```bash
./fetch_bookii_books.sh "/path/to/your/bookii"
```

## How It Works

The script uses two data sources:

1. **Bookii Medienservice API** (primary)
   - Official Bookii API
   - Works for all Bookii books
   - Gets metadata, version, and publisher info
   - Downloads from streaming server

2. **TING Backup Server** (fallback)
   - Legacy TING archive server
   - Works for older TING-compatible books
   - Automatically tried if Bookii API fails

### Download Process

```
User scans book → Book ID added to tbd.txt → Script reads tbd.txt
                                                      ↓
                                           Try Bookii API
                                                      ↓
                                              Found? → Download
                                                      ↓
                                              Not found? → Try TING
                                                      ↓
                                              Download complete
```

## Requirements

- **Bash** 3.2+ (macOS/Linux)
- **curl** (for downloads)
- **python3** (for JSON parsing)
- **Internet connection**

## Installation

```bash
# Clone the repository
git clone https://github.com/t2d/bookii-downloader.git
cd bookii-downloader

# Make the script executable
chmod +x fetch_bookii_books.sh

# Run tests (optional)
./test_fetch.sh
```

## Testing

The project includes a comprehensive test suite:

```bash
./test_fetch.sh
```

**Test Coverage:**
- ✅ API connectivity (Bookii & TING)
- ✅ Metadata parsing and version resolution
- ✅ URL format validation
- ✅ Script integration and error handling
- ✅ Shellcheck compliance

See [TESTING.md](TESTING.md) for details.

## Examples

### Example 1: Download a specific Bookii book

```bash
./fetch_bookii_books.sh "/Volumes/NO NAME" 9550
```

Output:
```
========================================
Bookii/TING Book Downloader
========================================

Downloading book 09550 (ID: 9550)...
  Checking Bookii API...
  Book: Bibel «hör» memo - Schweizerdeutsch
  Author: Marcus & Conny Witzig
  Publisher ID: 10, Version: 2
  Creating description file...
  Downloading thumbnail...
  Downloading book data (this may take a while)...
  Successfully downloaded book 09550 (15M) via Bookii API

========================================
Downloads complete!
  Successful: 1
  Failed: 0
========================================
```

### Example 2: Download a TING book

```bash
./fetch_bookii_books.sh "/Volumes/NO NAME" 5001
```

The script will:
1. Try Bookii API first (returns empty)
2. Automatically fall back to TING server
3. Download from TING archive

## File Structure

```
/Volumes/NO NAME/
├── book/
│   ├── 09550_en.kii    # Book data
│   ├── 09550_en.png    # Thumbnail
│   └── 09550_en.txt    # Metadata
└── configure/
    └── tbd.txt         # Pending downloads
```

## API Documentation

### Bookii Medienservice API

```bash
# Get all book versions
GET https://www.bookii-medienservice.de/Medienserver-1.0/api/download/versions/

# Get book metadata
GET https://www.bookii-medienservice.de/Medienserver-1.0/api/download/medias?mids="9550"

# Download book data
GET https://www.bookii-streamingservice.de/files/{publisherId}/{mid}/{version}/{mid_5digit}_en.kii

# Download thumbnail
GET https://www.bookii-streamingservice.de/files/{publisherId}/{mid}/{mid}_en.png
```

### TING Backup Server

```bash
# Get description
GET http://13.80.138.170/book-files/get-description/id/{id}/area/en/

# Download thumbnail
GET http://13.80.138.170/book-files/get/id/{id}/area/en/type/thumb/

# Download book data
GET http://13.80.138.170/book-files/get/id/{id}/area/en/type/archive/
```

## Troubleshooting

### Book not found

```
Book not found in Bookii API
Trying TING backup server...
Failed to download description
```

**Solution**: The book ID may not exist in either database. Verify the book ID is correct.

### Network errors

```
Failed to fetch from Bookii API
```

**Solution**: Check your internet connection. The script requires access to both Bookii and TING servers.

### Mount path errors

```
Error: Mount path '/Volumes/NO NAME' does not exist.
```

**Solution**: Make sure your Bookii pen is connected and mounted. Check the mount path with `ls /Volumes/`.

## Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Run tests: `./test_fetch.sh`
4. Run shellcheck: `shellcheck fetch_bookii_books.sh`
5. Submit a pull request

## Credits

Based on reverse-engineering work from [this Reddit post](https://www.reddit.com/r/de_EDV/comments/w2z1ea/).

## License

MIT License - See [LICENSE](LICENSE) file for details.

## Disclaimer

This tool is for personal use only. Please respect copyright laws and only download books you own.

---

**Note**: This is an unofficial tool and is not affiliated with, endorsed by, or connected to Tessloff Verlag, Bookii, or TING.
