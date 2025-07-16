# Music Collector - Windows Python Script

A Windows Python script that scans your music library, identifies music by ID3 tags, and copies a specified amount of data to a destination folder.

## Features

- **Genre-based filtering**: Find music by specific genres (country, rock, jazz, etc.)
- **Random selection**: Collect random music files up to a target size
- **Size-based collection**: Specify exact size limits (e.g., 1GB, 500MB)
- **Progress tracking**: Real-time progress updates and detailed logging
- **Duplicate handling**: Automatically handles duplicate filenames
- **Detailed reporting**: Generates comprehensive collection reports
- **Metadata extraction**: Uses ffprobe for reliable ID3 tag reading

## Requirements

- **Python 3.6+** (Anaconda recommended)
- **ffmpeg/ffprobe**: For metadata extraction
- **Windows OS**: Designed for Windows file systems

## Installation

1. **Install Python/Anaconda**: Download and install Anaconda from https://www.anaconda.com/

2. **Install ffmpeg**: 
   - Download from https://ffmpeg.org/download.html
   - Extract to `C:\Users\cayuse\ffmpeg-2025-07-10-git-82aeee3c19-essentials_build\bin\`
   - Ensure `ffprobe.exe` is in this directory

3. **Download the script**: Save `music_collector.py` and `collect_music.bat` to your desired directory

## Usage

### Command Line Usage

```bash
# Basic usage - collect country music
python music_collector.py --source "C:\Music" --dest "C:\Country_Collection" --genre country --size 1gb

# Random selection
python music_collector.py --source "C:\Music" --dest "C:\Random_Collection" --random --size 500mb

# Different genre
python music_collector.py --source "C:\Music" --dest "C:\Rock_Collection" --genre rock --size 2gb

# Limit number of files to scan
python music_collector.py --source "C:\Music" --dest "C:\Jazz_Collection" --genre jazz --size 1gb --max-files 10000

# Custom ffmpeg path
python music_collector.py --source "C:\Music" --dest "C:\Blues_Collection" --genre blues --size 1gb --ffmpeg-path "C:\ffmpeg\bin"
```

### Batch File Usage (Easier)

```bash
# Collect country music
collect_music.bat "C:\Music" "C:\Country_Collection" country 1gb

# Random selection
collect_music.bat "C:\Music" "C:\Random_Collection" random 500mb

# Rock music
collect_music.bat "C:\Music" "C:\Rock_Collection" rock 2gb
```

## Supported Genres

The script recognizes these genres and their variations:

- **country**: country, country & western, country and western, americana
- **rock**: rock, hard rock, soft rock, classic rock, alternative rock
- **jazz**: jazz, smooth jazz, bebop, swing
- **blues**: blues, rhythm and blues, r&b
- **pop**: pop, popular
- **classical**: classical, orchestral, symphony
- **electronic**: electronic, edm, dance, techno, house
- **hip hop**: hip hop, rap, hip-hop
- **folk**: folk, folk rock
- **reggae**: reggae, ska
- **metal**: metal, heavy metal, death metal, black metal
- **punk**: punk, punk rock
- **soul**: soul, motown
- **funk**: funk, funk rock
- **disco**: disco
- **gospel**: gospel, christian
- **world**: world, world music, ethnic
- **soundtrack**: soundtrack, score, film score
- **children**: children, kids, children's
- **comedy**: comedy, humor, humour

## Size Formats

Supported size formats:
- `1gb` = 1 gigabyte
- `500mb` = 500 megabytes
- `2.5gb` = 2.5 gigabytes
- `100kb` = 100 kilobytes
- `1b` = 1 byte

## Output

The script creates:

1. **Copied music files** in the destination directory
2. **Detailed log file** (`music_collector.log`) with progress and errors
3. **Collection report** (`collection_report.txt`) in the destination directory containing:
   - Summary statistics
   - Genre breakdown
   - Complete file list with metadata
   - Collection date and details

## Examples

### Example 1: Collect 1GB of Country Music
```bash
python music_collector.py --source "C:\Users\cayuse\Music" --dest "C:\Country_Collection" --genre country --size 1gb
```

### Example 2: Collect 500MB of Random Music
```bash
python music_collector.py --source "C:\Users\cayuse\Music" --dest "C:\Random_Collection" --random --size 500mb
```

### Example 3: Collect 2GB of Rock Music (Limited Scan)
```bash
python music_collector.py --source "C:\Users\cayuse\Music" --dest "C:\Rock_Collection" --genre rock --size 2gb --max-files 5000
```

## Troubleshooting

### Common Issues

1. **"ffprobe not found" error**
   - Ensure ffprobe.exe is in the specified directory
   - Use `--ffmpeg-path` to specify custom location
   - Download ffmpeg from https://ffmpeg.org/download.html

2. **"No MP3 files found"**
   - Check that your source directory contains .mp3 files
   - Ensure files have valid ID3 tags
   - Try with `--max-files` to limit scanning

3. **"No files matching genre"**
   - Check that your MP3 files have genre tags
   - Try a different genre or use `--random`
   - Check the log file for details

4. **Permission errors**
   - Run as administrator if needed
   - Check file permissions on source and destination directories

5. **Slow performance**
   - Use `--max-files` to limit the number of files scanned
   - Consider scanning smaller subdirectories first

### Performance Tips

- **Limit file scanning**: Use `--max-files 10000` for large libraries
- **Scan subdirectories**: Process one genre folder at a time
- **Use SSD**: Faster read/write speeds for large collections
- **Close other applications**: Free up system resources

### Log Files

The script creates detailed logs in `music_collector.log`:
- Progress updates every 100 files
- Error details for failed operations
- Metadata extraction issues
- File copy status

## Advanced Usage

### Custom Genre Matching

You can modify the `genre_mappings` dictionary in the script to add custom genre variations:

```python
self.genre_mappings = {
    'country': ['country', 'country & western', 'country and western', 'americana', 'your_custom_genre'],
    # ... other genres
}
```

### Batch Processing Multiple Genres

Create a batch script to process multiple genres:

```batch
@echo off
python music_collector.py --source "C:\Music" --dest "C:\Collections\Country" --genre country --size 1gb
python music_collector.py --source "C:\Music" --dest "C:\Collections\Rock" --genre rock --size 1gb
python music_collector.py --source "C:\Music" --dest "C:\Collections\Jazz" --genre jazz --size 1gb
```

## File Structure

```
utilities/
├── music_collector.py      # Main Python script
├── collect_music.bat       # Windows batch file
├── MUSIC_COLLECTOR_README.md  # This documentation
└── music_collector.log     # Generated log file
```

## Technical Details

- **Metadata extraction**: Uses ffprobe JSON output for reliable tag reading
- **File handling**: Supports Windows long paths and special characters
- **Memory efficient**: Processes files one at a time
- **Error recovery**: Continues processing even if individual files fail
- **Unicode support**: Handles international characters in filenames and tags

## Support

For issues or questions:
1. Check the log file (`music_collector.log`) for detailed error information
2. Ensure ffprobe is properly installed and accessible
3. Verify your MP3 files have valid ID3 tags
4. Test with a small subset of files first 