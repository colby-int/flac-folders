# flac-folders

Simple cleanup script for those with a folder full of individual FLAC files. Organises FLAC music files into a structured directory hierarchy using embedded metadata and MusicBrainz API lookups.

## Features

- **Interactive directory configuration** with Finder integration for macOS
- **File validation and cleanup** - automatically removes original files after successful copy verification
- **Metadata validation** - ensures copied files maintain identical metadata
- Automatically organises FLAC files into `Artist > Album (Year) > Track` structure
- Extracts metadata from FLAC files using `metaflac`
- Queries MusicBrainz API for missing album information
- Handles multiple filename formats:
  - `Artist - Title.flac`
  - `01 - Title.flac` (with context detection)
  - Various separators (-, –, _-_)
- Intelligent fallback system for incomplete metadata
- Creates special folders for files that need manual review
- Respects MusicBrainz API rate limits

## Requirements

- `metaflac` (from FLAC tools package)
- `curl`
- `python3`
- Bash 4.0+

### Installing Dependencies

**macOS (Homebrew):**
```bash
brew install flac curl python3
```

**Ubuntu/Debian:**
```bash
sudo apt-get install flac curl python3
```

**CentOS/RHEL:**
```bash
sudo yum install flac curl python3
```

## Installation

1. Download the script:
```bash
curl -O https://raw.githubusercontent.com/colby-int/flac-folders/main/flac.sh
```

2. Make it executable:
```bash
chmod +x flac.sh
```

3. Optionally, move to your PATH:
```bash
sudo mv flac.sh /usr/local/bin/flac-folders
```

## Usage

### Interactive Setup

When you run the script, it will first prompt you to configure directories:

1. **Music Library Directory** - Where organised files will be placed
2. **Check Directory** - Where problematic files are stored for manual review

The script uses macOS Finder dialogs for easy directory selection.

### Basic Usage

```bash
./flac.sh "Artist Name - Song Title.flac"
./flac.sh *.flac
./flac.sh /path/to/music/*.flac
```

### Examples

**Single file with artist and title:**
```bash
./flac.sh "Pink Floyd - Comfortably Numb.flac"
```

**Multiple files:**
```bash
./flac.sh "01 - Another Brick In The Wall.flac" "02 - Mother.flac"
```

**All FLAC files in current directory:**
```bash
./flac.sh *.flac
```

## How It Works

### Metadata Extraction Priority

1. **Embedded FLAC metadata** (using `metaflac`)
   - ARTIST/ALBUMARTIST
   - TITLE
   - ALBUM
   - DATE/YEAR
   - TRACKNUMBER/TRACK

2. **Filename parsing**
   - `Artist - Title.flac`
   - `01 - Title.flac` (numbered tracks)

3. **Context detection** (for numbered tracks)
   - Searches directory for context files
   - Analyzes parent directory names
   - Queries MusicBrainz for album information

4. **MusicBrainz API fallback**
   - Queries for missing album/year information
   - Respects 1-second rate limit

### Directory Structure

The script creates the following structure:

```
~/Music/Organised/
├── Artist Name/
│   ├── Album Name (Year)/
│   │   ├── 01 - Track Title.flac
│   │   └── 02 - Another Track.flac
│   └── Another Album (Year)/
│       └── 01 - Track.flac
├── !CHECK/
│   ├── Unsure/
│   │   └── Artist Name/
│   │       └── incomplete-metadata.flac
│   └── Failed/
│       └── no-artist-info.flac
```

### Special Directories

- **!CHECK/Unsure/**: Files with artist but no album information
- **!CHECK/Failed/**: Files with no artist information

## Configuration

### Interactive Configuration

The script now includes interactive directory configuration when you run it:

- **Current directories are displayed** with colour coding
- **Y/N prompts** allow you to change each directory
- **Finder integration** opens native macOS dialogs for easy selection
- **Configuration summary** shows all settings before proceeding



### File Processing Features

- **Metadata validation**: Ensures copied files have identical metadata to originals
- **File integrity verification**: Uses checksums to verify successful copying
- **Automatic cleanup**: Removes original files only after successful validation
- **Error handling**: Keeps original files if validation fails

## Tips

### For Numbered Tracks

When processing numbered tracks (like `01 - Title.flac`), include at least one file with artist information in the same directory:

```
my-album/
├── Artist Name - Any Song.flac  # Provides artist context
├── 01 - First Track.flac
├── 02 - Second Track.flac
└── 03 - Third Track.flac
```

Alternatively, name the parent directory as `Artist - Album`:

```
Pink Floyd - The Wall/
├── 01 - Another Brick In The Wall.flac
├── 02 - Mother.flac
└── 03 - Goodbye Blue Sky.flac
```

### Best Practices

1. **Run on small batches first** to test organisation
2. **Review !CHECK directories** regularly for files needing manual attention
3. **Use embedded metadata** when possible for best results
4. **Trust the validation system** - original files are only removed after successful verification

## Troubleshooting

### Common Issues

**"metaflac: command not found"**
```bash
# Install FLAC tools
brew install flac  # macOS
sudo apt-get install flac  # Ubuntu/Debian
```

**Network errors with MusicBrainz**
- Check internet connection
- The script automatically retries with rate limiting
- Some files may end up in !CHECK/Unsure if lookup fails

**File validation errors**
- Original files are preserved if validation fails
- Check file permissions and available disk space
- Corrupted files will be detected and originals kept safe

**Permission errors**
```bash
# Make sure the script is executable
chmod +x flac.sh

# Check write permissions for destination directories
ls -la ~/Music/
```

### Debug Mode

For verbose output, you can modify the script to show debug information by uncommenting debug lines or adding:

```bash
set -x  # Add at top of script for full debug output
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test with various file types
5. Submit a pull request

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- [MusicBrainz](https://musicbrainz.org/) for providing the music metadata API
- [FLAC](https://xiph.org/flac/) tools for metadata extraction
- Contributors and testers

## Support

If you encounter issues:

1. Check the [Troubleshooting](#troubleshooting) section
2. Search existing [GitHub Issues](https://github.com/colby-int/flac-folders/issues)
3. Create a new issue with:
   - Your operating system
   - Sample filenames that aren't working
   - Error messages
   - Expected vs actual behavior
