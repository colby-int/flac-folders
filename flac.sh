#!/bin/bash

# flac-folders
# Organises FLAC files into Artist > Album (Year) > Track structure
# Uses MusicBrainz API for metadata lookup

# Configuration
MUSIC_LIBRARY_PATH="/Select/PathTo/Music" # Change this to where you'd like it to output
CHECK_PATH="/Select/PathTo/Music/!CHECK" # This will have files that it couldn't find data for
UNSURE_PATH="${CHECK_PATH}/Unsure" # This will have files that it tentatively applied from MusicBrainz
FAILED_PATH="${CHECK_PATH}/Failed"
RATE_LIMIT_DELAY=1  # MusicBrainz requires 1 second between requests
USER_AGENT="flac-folders/1.0 (https://github.com/colby-int/flac-folders)" 
# Colours for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Colour

# Global cache for album context
declare -A ALBUM_CACHE

# Function to URL encode strings
urlencode() {
    local string="${1}"
    python3 -c "import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1]))" "$string"
}

# Function to clean filename for directory creation
clean_filename() {
    echo "$1" | sed 's/[<>:"/\\|?*]//g' | sed 's/\.$//' | sed 's/^\.//g'
}

# Function to detect if filename is track number format
is_track_format() {
    local filename="$1"
    local base="${filename%.flac}"
    
    # Check for patterns like "01 - Title", "1. Title", "01_Title", etc.
    if [[ "$base" =~ ^[0-9]{1,2}[[:space:]]*[-._][[:space:]]*.+ ]]; then
        return 0
    fi
    return 1
}

# Function to extract track number and title from track format
extract_track_info() {
    local filename="$1"
    local base="${filename%.flac}"
    
    # Extract track number and title
    if [[ "$base" =~ ^([0-9]{1,2})[[:space:]]*[-._][[:space:]]*(.+)$ ]]; then
        echo "track:${BASH_REMATCH[1]}"
        echo "title:${BASH_REMATCH[2]}"
        return 0
    fi
    return 1
}

# Function to find album context from directory
find_album_context() {
    local filepath="$1"
    local directory=$(dirname "$filepath")
    
    echo -e "${BLUE}  → Analysing directory for album context...${NC}"
    
    # Check cache first
    if [[ -n "${ALBUM_CACHE[$directory]}" ]]; then
        echo "${ALBUM_CACHE[$directory]}"
        return 0
    fi
    
    # Look for files with artist information in the same directory
    local context_found=""
    
    # First, try to find any file with "Artist - Title" format
    for file in "$directory"/*.flac; do
        [ -f "$file" ] || continue
        local basename=$(basename "$file")
        
        if [[ "$basename" == *" - "* ]] && ! is_track_format "$basename"; then
            # This might be "Artist - Title" format
            local artist="${basename%% - *}"
            
            # Verify this isn't just a number
            if ! [[ "$artist" =~ ^[0-9]+$ ]]; then
                echo -e "${BLUE}    Found context from: $basename${NC}"
                
                # Query MusicBrainz for this file to get album info
                local mb_info=$(query_musicbrainz "$artist" "${basename#* - }")
                if [ -n "$mb_info" ]; then
                    context_found="$mb_info"
                    break
                fi
            fi
        fi
    done
    
    # Try to extract from parent directory name (often "Artist - Album" or "Album")
    if [ -z "$context_found" ]; then
        local parent_dir=$(basename "$directory")
        
        # Check if parent directory has artist - album format
        if [[ "$parent_dir" == *" - "* ]]; then
            local potential_artist="${parent_dir%% - *}"
            local potential_album="${parent_dir#* - }"
            
            echo -e "${BLUE}    Checking parent directory: $parent_dir${NC}"
            
            # Try to verify with MusicBrainz
            local query="artist:\"${potential_artist}\" AND release:\"${potential_album}\""
            local encoded_query=$(urlencode "$query")
            local url="https://musicbrainz.org/ws/2/release?query=${encoded_query}&fmt=json&limit=1"
            
            sleep $RATE_LIMIT_DELAY
            local response=$(curl -s -H "User-Agent: ${USER_AGENT}" "$url")
            
            # Check if curl succeeded
            if [ $? -ne 0 ] || [ -z "$response" ]; then
                echo -e "${RED}    Network error querying MusicBrainz${NC}"
                return 1
            fi
            
            local album_info=$(python3 -c "
import json
import sys

try:
    response = sys.argv[1]
    data = json.loads(response)
    if 'releases' in data and len(data['releases']) > 0:
        release = data['releases'][0]
        artist_name = ''
        if 'artist-credit' in release and len(release['artist-credit']) > 0:
            artist_name = release['artist-credit'][0]['name']
        
        album_name = release.get('title', '')
        year = ''
        if 'date' in release:
            year = release['date'][:4] if len(release['date']) >= 4 else ''
        
        if artist_name:
            print(f'artist:{artist_name}')
        if album_name:
            print(f'album:{album_name}')
        if year:
            print(f'year:{year}')
except (json.JSONDecodeError, IndexError, KeyError, AttributeError):
    pass
except Exception as e:
    print(f'Error parsing MusicBrainz response: {e}', file=sys.stderr)
" "$response")
            
            if [ -n "$album_info" ]; then
                context_found="$album_info"
            fi
        fi
    fi
    
    # Cache the result
    if [ -n "$context_found" ]; then
        ALBUM_CACHE[$directory]="$context_found"
    fi
    
    echo "$context_found"
}

# Function to extract metadata from FLAC file using metaflac
extract_flac_metadata() {
    local filepath="$1"
    
    # Check if file exists
    if [ ! -f "$filepath" ]; then
        return 1
    fi
    
    # Extract common metadata tags
    local artist=$(metaflac --show-tag=ARTIST "$filepath" 2>/dev/null | cut -d'=' -f2-)
    local albumartist=$(metaflac --show-tag=ALBUMARTIST "$filepath" 2>/dev/null | cut -d'=' -f2-)
    local title=$(metaflac --show-tag=TITLE "$filepath" 2>/dev/null | cut -d'=' -f2-)
    local album=$(metaflac --show-tag=ALBUM "$filepath" 2>/dev/null | cut -d'=' -f2-)
    local date=$(metaflac --show-tag=DATE "$filepath" 2>/dev/null | cut -d'=' -f2-)
    local year=$(metaflac --show-tag=YEAR "$filepath" 2>/dev/null | cut -d'=' -f2-)
    local tracknumber=$(metaflac --show-tag=TRACKNUMBER "$filepath" 2>/dev/null | cut -d'=' -f2-)
    local track=$(metaflac --show-tag=TRACK "$filepath" 2>/dev/null | cut -d'=' -f2-)
    
    # Use ALBUMARTIST if available, otherwise fall back to ARTIST
    if [ -n "$albumartist" ]; then
        artist="$albumartist"
    fi
    
    # Extract year from DATE if YEAR is not available
    if [ -z "$year" ] && [ -n "$date" ]; then
        year=$(echo "$date" | grep -o '^[0-9]\{4\}')
    fi
    
    # Use TRACKNUMBER if available, otherwise fall back to TRACK
    if [ -z "$tracknumber" ] && [ -n "$track" ]; then
        tracknumber="$track"
    fi
    
    # Remove track count if present (e.g., "5/12" -> "5")
    if [ -n "$tracknumber" ]; then
        tracknumber=$(echo "$tracknumber" | cut -d'/' -f1)
    fi
    
    # Output results
    if [ -n "$artist" ]; then
        echo "artist:$artist"
    fi
    if [ -n "$title" ]; then
        echo "title:$title"
    fi
    if [ -n "$album" ]; then
        echo "album:$album"
    fi
    if [ -n "$year" ]; then
        echo "year:$year"
    fi
    if [ -n "$tracknumber" ]; then
        echo "track:$tracknumber"
    fi
    
    return 0
}

# Function to extract artist and title from filename
extract_artist_title() {
    local filename="$1"
    # Remove .flac extension
    local base="${filename%.flac}"
    
    # Try to split by " - "
    if [[ "$base" == *" - "* ]]; then
        artist="${base%% - *}"
        title="${base#* - }"
        echo "artist:$artist"
        echo "title:$title"
        return 0
    fi
    
    # Try to split by " – " (em dash)
    if [[ "$base" == *" – "* ]]; then
        artist="${base%% – *}"
        title="${base#* – }"
        echo "artist:$artist"
        echo "title:$title"
        return 0
    fi
    
    # Try to split by "_-_"
    if [[ "$base" == *"_-_"* ]]; then
        artist="${base%%_-_*}"
        title="${base#*_-_}"
        echo "artist:$artist"
        echo "title:$title"
        return 0
    fi
    
    return 1
}

# Function to query MusicBrainz API
query_musicbrainz() {
    local artist="$1"
    local title="$2"
    
    # URL encode the parameters
    local encoded_artist=$(urlencode "$artist")
    local encoded_title=$(urlencode "$title")
    
    # Build query
    local query="artist:\"${artist}\" AND recording:\"${title}\""
    local encoded_query=$(urlencode "$query")
    
    # Query MusicBrainz
    local url="https://musicbrainz.org/ws/2/recording?query=${encoded_query}&fmt=json&limit=5"
    
    # Make request with user agent
    local response=$(curl -s -H "User-Agent: ${USER_AGENT}" "$url")
    
    # Check if curl succeeded
    if [ $? -ne 0 ] || [ -z "$response" ]; then
        echo -e "${RED}  Network error querying MusicBrainz${NC}"
        return 1
    fi
    
    # Parse response using Python (macOS has Python3 by default)
    python3 -c "
import json
import sys

try:
    response = sys.argv[1]
    data = json.loads(response)
    if 'recordings' in data and len(data['recordings']) > 0:
        recording = data['recordings'][0]
        
        # Get artist info
        artist_name = ''
        if 'artist-credit' in recording and len(recording['artist-credit']) > 0:
            artist_name = recording['artist-credit'][0]['name']
        
        # Get album info from first release
        album_name = ''
        album_year = ''
        track_number = ''
        
        if 'releases' in recording and len(recording['releases']) > 0:
            release = recording['releases'][0]
            album_name = release.get('title', '')
            
            # Get year from date
            if 'date' in release:
                album_year = release['date'][:4] if len(release['date']) >= 4 else ''
            
            # Get track number if available
            if 'media' in release and len(release['media']) > 0:
                media = release['media'][0]
                if 'track' in media and len(media['track']) > 0:
                    for track in media['track']:
                        if track.get('id') == recording.get('id'):
                            track_number = str(track.get('number', ''))
                            break
        
        # Output results
        if artist_name:
            print(f'artist:{artist_name}')
        if album_name:
            print(f'album:{album_name}')
        if album_year:
            print(f'year:{album_year}')
        if track_number:
            print(f'track:{track_number}')
except (json.JSONDecodeError, IndexError, KeyError, AttributeError):
    pass
except Exception as e:
    print(f'Error parsing MusicBrainz response: {e}', file=sys.stderr)
    sys.exit(1)
" "$response"
}

# Function to validate metadata consistency between source and destination
validate_metadata() {
    local source_file="$1"
    local dest_file="$2"
    
    if [ ! -f "$source_file" ] || [ ! -f "$dest_file" ]; then
        return 1
    fi
    
    # Extract metadata from both files
    local source_metadata=$(extract_flac_metadata "$source_file")
    local dest_metadata=$(extract_flac_metadata "$dest_file")
    
    # Compare key metadata fields
    local source_artist=$(echo "$source_metadata" | grep "^artist:" | cut -d':' -f2-)
    local dest_artist=$(echo "$dest_metadata" | grep "^artist:" | cut -d':' -f2-)
    local source_title=$(echo "$source_metadata" | grep "^title:" | cut -d':' -f2-)
    local dest_title=$(echo "$dest_metadata" | grep "^title:" | cut -d':' -f2-)
    local source_album=$(echo "$source_metadata" | grep "^album:" | cut -d':' -f2-)
    local dest_album=$(echo "$dest_metadata" | grep "^album:" | cut -d':' -f2-)
    
    # Check if metadata matches
    if [ "$source_artist" = "$dest_artist" ] && [ "$source_title" = "$dest_title" ] && [ "$source_album" = "$dest_album" ]; then
        return 0
    else
        return 1
    fi
}

# Function to verify file integrity using checksums
verify_file_copy() {
    local source_file="$1"
    local dest_file="$2"
    
    if [ ! -f "$source_file" ] || [ ! -f "$dest_file" ]; then
        return 1
    fi
    
    # Compare file sizes first (quick check)
    local source_size=$(stat -f%z "$source_file" 2>/dev/null)
    local dest_size=$(stat -f%z "$dest_file" 2>/dev/null)
    
    if [ "$source_size" != "$dest_size" ]; then
        return 1
    fi
    
    # Compare checksums for thorough verification
    local source_checksum=$(md5 -q "$source_file")
    local dest_checksum=$(md5 -q "$dest_file")
    
    if [ "$source_checksum" = "$dest_checksum" ]; then
        return 0
    else
        return 1
    fi
}

# Function to select directory using Finder
select_directory() {
    local prompt="$1"
    local current_dir="$2"
    
    echo "Opening Finder to select directory..."
    local selected_dir=$(osascript -e "
        tell application \"Finder\"
            activate
            set selectedFolder to choose folder with prompt \"$prompt\" default location \"$current_dir\"
            return POSIX path of selectedFolder
        end tell
    " 2>/dev/null)
    
    if [ -n "$selected_dir" ]; then
        # Remove trailing slash if present
        selected_dir="${selected_dir%/}"
        echo "$selected_dir"
        return 0
    else
        return 1
    fi
}

# Function to prompt for directory configuration
configure_directory() {
    local var_name="$1"
    local description="$2"
    local current_value="$3"
    
    echo ""
    echo -e "${BLUE}$description${NC}"
    echo -e "Current: ${YELLOW}$current_value${NC}"
    echo -n "Would you like to change this? (y/N): "
    read -r response
    
    if [[ "$response" =~ ^[Yy]$ ]]; then
        local new_dir=$(select_directory "$description" "$current_value")
        if [ $? -eq 0 ] && [ -n "$new_dir" ]; then
            echo -e "Selected: ${GREEN}$new_dir${NC}"
            # Update the variable dynamically
            eval "$var_name=\"$new_dir\""
        else
            echo -e "${YELLOW}No directory selected, keeping current setting${NC}"
        fi
    fi
}

# Function to initialize and configure directories
init_directories() {
    echo "flac-folders - Directory Configuration"
    echo "======================================"
    echo ""
    echo "Please review and configure the following directories:"
    
    # Configure Music Library Path
    configure_directory "MUSIC_LIBRARY_PATH" "Music Library Output Directory" "$MUSIC_LIBRARY_PATH"
    
    # Configure Check Path
    configure_directory "CHECK_PATH" "Check Directory (for problematic files)" "$CHECK_PATH"
    
    # Update dependent paths
    UNSURE_PATH="${CHECK_PATH}/Unsure"
    FAILED_PATH="${CHECK_PATH}/Failed"
    
    echo ""
    echo "Final Configuration:"
    echo "==================="
    echo -e "Music Library: ${GREEN}$MUSIC_LIBRARY_PATH${NC}"
    echo -e "Check Directory: ${GREEN}$CHECK_PATH${NC}"
    echo -e "  - Unsure: ${GREEN}$UNSURE_PATH${NC}"
    echo -e "  - Failed: ${GREEN}$FAILED_PATH${NC}"
    echo ""
    echo -n "Proceed with these settings? (Y/n): "
    read -r proceed
    
    if [[ "$proceed" =~ ^[Nn]$ ]]; then
        echo "Configuration cancelled."
        exit 0
    fi
    
    # Create directories if they don't exist
    mkdir -p "$MUSIC_LIBRARY_PATH"
    mkdir -p "$CHECK_PATH"
    mkdir -p "$UNSURE_PATH"
    mkdir -p "$FAILED_PATH"
    
    echo -e "${GREEN}Configuration complete!${NC}"
    echo ""
}

# Function to move and organise file
organise_file() {
    local filepath="$1"
    local filename=$(basename "$filepath")
    
    echo -e "${YELLOW}Processing: ${filename}${NC}"
    
    # First, try to extract metadata from the FLAC file itself
    echo "  → Extracting embedded metadata..."
    local metadata=$(extract_flac_metadata "$filepath")
    
    local artist=""
    local title=""
    local album=""
    local year=""
    local track_num=""
    
    if [ -n "$metadata" ]; then
        # Parse embedded metadata
        artist=$(echo "$metadata" | grep "^artist:" | cut -d':' -f2-)
        title=$(echo "$metadata" | grep "^title:" | cut -d':' -f2-)
        album=$(echo "$metadata" | grep "^album:" | cut -d':' -f2-)
        year=$(echo "$metadata" | grep "^year:" | cut -d':' -f2-)
        track_num=$(echo "$metadata" | grep "^track:" | cut -d':' -f2-)
        
        echo "  → Found embedded metadata: Artist='$artist', Title='$title', Album='$album'"
        if [ -n "$year" ]; then
            echo "  → Year: $year"
        fi
        if [ -n "$track_num" ]; then
            echo "  → Track: $track_num"
        fi
    fi
    
    # If we don't have complete metadata, try filename parsing and MusicBrainz
    if [ -z "$artist" ] || [ -z "$title" ] || [ -z "$album" ]; then
        echo "  → Embedded metadata incomplete, trying filename parsing..."
        
        # Check if this is a track number format
        if is_track_format "$filename"; then
            echo "  → Detected track number format"
            
            # Extract track info from filename
            local track_info=$(extract_track_info "$filename")
            local filename_track=$(echo "$track_info" | grep "^track:" | cut -d':' -f2-)
            local filename_title=$(echo "$track_info" | grep "^title:" | cut -d':' -f2-)
            
            # Use filename info if not available from metadata
            if [ -z "$track_num" ]; then
                track_num="$filename_track"
            fi
            if [ -z "$title" ]; then
                title="$filename_title"
            fi
            
            # Find album context from directory if we don't have it
            if [ -z "$artist" ] || [ -z "$album" ]; then
                local context=$(find_album_context "$filepath")
                
                if [ -n "$context" ]; then
                    if [ -z "$artist" ]; then
                        artist=$(echo "$context" | grep "^artist:" | cut -d':' -f2-)
                    fi
                    if [ -z "$album" ]; then
                        album=$(echo "$context" | grep "^album:" | cut -d':' -f2-)
                    fi
                    if [ -z "$year" ]; then
                        year=$(echo "$context" | grep "^year:" | cut -d':' -f2-)
                    fi
                fi
            fi
            
        else
            # Standard "Artist - Title" format
            local info=$(extract_artist_title "$filename")
            if [ $? -eq 0 ]; then
                # Parse extracted info
                local filename_artist=$(echo "$info" | grep "^artist:" | cut -d':' -f2-)
                local filename_title=$(echo "$info" | grep "^title:" | cut -d':' -f2-)
                
                # Use filename info if not available from metadata
                if [ -z "$artist" ]; then
                    artist="$filename_artist"
                fi
                if [ -z "$title" ]; then
                    title="$filename_title"
                fi
                
                echo "  → Found from filename: Artist='$artist', Title='$title'"
            fi
        fi
    fi
    
    # Final fallback: try MusicBrainz if we still don't have complete info
    if [ -n "$artist" ] && [ -n "$title" ] && [ -z "$album" ]; then
        echo "  → Trying MusicBrainz as fallback for missing album info..."
        sleep $RATE_LIMIT_DELAY
        local mb_info=$(query_musicbrainz "$artist" "$title")
        
        if [ -n "$mb_info" ]; then
            # Parse MusicBrainz results
            local mb_artist=$(echo "$mb_info" | grep "^artist:" | cut -d':' -f2-)
            local mb_album=$(echo "$mb_info" | grep "^album:" | cut -d':' -f2-)
            local mb_year=$(echo "$mb_info" | grep "^year:" | cut -d':' -f2-)
            local mb_track=$(echo "$mb_info" | grep "^track:" | cut -d':' -f2-)
            
            # Use MusicBrainz data to fill in missing info
            if [ -z "$album" ] && [ -n "$mb_album" ]; then
                album="$mb_album"
            fi
            if [ -z "$year" ] && [ -n "$mb_year" ]; then
                year="$mb_year"
            fi
            if [ -z "$track_num" ] && [ -n "$mb_track" ]; then
                track_num="$mb_track"
            fi
            
            echo "  → MusicBrainz provided: Album='$album', Year='$year'"
        fi
    fi
    
    # Ensure we have minimum required info
    if [ -z "$artist" ] || [ "$artist" == "Unknown Artist" ]; then
        echo -e "${YELLOW}  → Moving to !CHECK/Failed (no artist information)${NC}"
        mkdir -p "$FAILED_PATH"
        local failed_dest="$FAILED_PATH/$filename"
        
        cp "$filepath" "$failed_dest"
        
        echo "  → Verifying file integrity..."
        if verify_file_copy "$filepath" "$failed_dest"; then
            echo "  → Verification successful, removing original file..."
            rm -f "$filepath"
            echo -e "${YELLOW}  → Moved to: ${FAILED_PATH}/${filename}${NC}"
            echo -e "${GREEN}    Original file cleaned up${NC}"
        else
            echo -e "${RED}  ✗ File verification failed - keeping original file${NC}"
            rm -f "$failed_dest"
        fi
        return 0
    fi
    
    # Check if we're unsure (have artist but no album)
    if [ -z "$album" ] && [ -n "$artist" ]; then
        echo -e "${YELLOW}  → Moving to !CHECK/Unsure (have artist but no album info)${NC}"
        mkdir -p "$UNSURE_PATH"
        
        # Create artist subfolder in Unsure
        local clean_artist=$(clean_filename "$artist")
        mkdir -p "$UNSURE_PATH/$clean_artist"
        local unsure_dest="$UNSURE_PATH/$clean_artist/$filename"
        
        cp "$filepath" "$unsure_dest"
        
        echo "  → Verifying file integrity..."
        if verify_file_copy "$filepath" "$unsure_dest"; then
            echo "  → Verification successful, removing original file..."
            rm -f "$filepath"
            echo -e "${YELLOW}  → Moved to: ${UNSURE_PATH}/$clean_artist/${filename}${NC}"
            echo -e "${GREEN}    Original file cleaned up${NC}"
        else
            echo -e "${RED}  ✗ File verification failed - keeping original file${NC}"
            rm -f "$unsure_dest"
        fi
        return 0
    fi
    
    # Clean names for filesystem
    local clean_artist=$(clean_filename "$artist")
    local clean_album=$(clean_filename "$album")
    
    # Build destination path
    if [ -n "$year" ]; then
        local album_folder="${clean_album} (${year})"
    else
        local album_folder="${clean_album}"
    fi
    
    local dest_dir="${MUSIC_LIBRARY_PATH}/${clean_artist}/${album_folder}"
    
    # Create destination directory
    mkdir -p "$dest_dir"
    
    # Build destination filename
    if [ -n "$track_num" ]; then
        # Pad track number with zero if single digit
        if [ ${#track_num} -eq 1 ]; then
            track_num="0${track_num}"
        fi
        local dest_filename="${track_num} - ${title}.flac"
    else
        local dest_filename="${title}.flac"
    fi
    
    local dest_path="${dest_dir}/${dest_filename}"
    
    # Move file
    cp "$filepath" "$dest_path"
    
    echo "  → Validating metadata consistency..."
    if ! validate_metadata "$filepath" "$dest_path"; then
        echo -e "${RED}  ✗ Metadata validation failed - removing copied file${NC}"
        rm -f "$dest_path"
        return 1
    fi
    
    echo "  → Verifying file integrity..."
    if ! verify_file_copy "$filepath" "$dest_path"; then
        echo -e "${RED}  ✗ File verification failed - removing copied file${NC}"
        rm -f "$dest_path"
        return 1
    fi
    
    echo "  → Validation successful, removing original file..."
    rm -f "$filepath"
    
    echo -e "${GREEN}  ✓ Organised to: ${dest_dir}/${dest_filename}${NC}"
    echo -e "${GREEN}    Artist: $artist | Album: $album${NC}"
    echo -e "${GREEN}    Original file cleaned up${NC}"
    return 0
}

# Main script
main() {
    # Initialize directories first
    init_directories
    
    # Check if flac files were provided as arguments
    if [ $# -eq 0 ]; then
        echo "Usage: $0 <flac_file1> [flac_file2] ..."
        echo "   or: $0 *.flac"
        echo ""
        echo "Examples:"
        echo "  $0 \"Artist Name - Song Title.flac\""
        echo "  $0 \"01 - Song Title.flac\""
        echo "  $0 *.flac"
        echo "  $0 /path/to/music/*.flac"
        echo ""
        echo "Tips:"
        echo "  - For numbered tracks (01 - Title.flac), include at least one"
        echo "    'Artist - Title.flac' file in the same directory"
        echo "  - Or name the parent directory as 'Artist - Album'"
        exit 1
    fi
    
    # Process each file
    local total_files=$#
    local processed=0
    local failed=0
    
    for file in "$@"; do
        if [ -f "$file" ] && [[ "$file" == *.flac ]]; then
            organise_file "$file"
            if [ $? -eq 0 ]; then
                ((processed++))
            else
                ((failed++))
            fi
        else
            echo -e "${RED}Skipping: $file (not a FLAC file)${NC}"
            ((failed++))
        fi
        echo ""
    done
    
    # Summary
    echo "===================="
    echo -e "${GREEN}Processed: ${processed}/${total_files} files${NC}"
    if [ $failed -gt 0 ]; then
        echo -e "${RED}Failed: ${failed} files${NC}"
    fi
}

# Run main function with all arguments
main "$@"