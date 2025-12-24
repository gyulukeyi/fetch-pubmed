# fetch-pubmed

**NOTE**

This is essentially a toy project for me learning _how-to-unix_ while learning ZSH and Perl. This script by no means would be the best or at least stable way to fetch metadata from PubMed's FTP. 

A simple zsh script for fetching and parsing PubMed citation data from NCBI's FTP server. This tool downloads PubMed baseline XML files, extracts article metadata (title, abstract, year, authors), and converts them into tab-separated value (TSV) format for easy processing and analysis.

## Features

- **Automated fetching**: Downloads PubMed baseline files directly from NCBI's FTP server
- **XML parsing**: Extracts key article metadata (title, abstract, publication year, authors)
- **TSV output**: Converts XML data into tab-separated format for easy import into databases or analysis tools
- **Chunked output**: Automatically splits large datasets into manageable files (100,000 records per file)
- **Configurable**: Customize year range, file numbers, and output directory
- **Easy installation**: Simple Makefile-based installation to your local system

## Requirements

- **zsh** (Z shell) - Required for the main script
- **perl** - Required for XML parsing
- **curl** - Required for downloading files from NCBI
- **gsplit** - GNU split utility (install via `brew install coreutils` on macOS)

## Installation

### Quick Start

1. Clone this repository:
   ```bash
   git clone <repository-url>
   cd fetch-pubmed
   ```

2. Check dependencies:
   ```bash
   make check
   ```

3. Install to your local system (defaults to `~/.local`):
   ```bash
   make install
   ```

   Or install to a custom location:
   ```bash
   make install PREFIX=/path/to/install
   ```

   To install system-wide (requires sudo):
   ```bash
   sudo make install PREFIX=/usr/local
   ```

After installation, you can run `fetch-pubmed` from anywhere in your terminal.

## Usage

### Using the Makefile

Run the full pipeline with default settings:
```bash
make run
```

This will:
- Create an `output/` directory
- Fetch PubMed files (default: files 1-1274 for year 25)
- Parse XML and convert to TSV
- Split output into chunks of 100,000 records

### Using the Script Directly

Run the script with custom parameters:
```bash
./bin/fetch-all.zsh -y 25 -s 1 -e 100 -o output
```

**Options:**
- `-y YEAR` - Year number (default: 25)
- `-s START` - Starting file number (default: 1)
- `-e END` - Ending file number (default: 1274)
- `-o OUTPUT_DIR` - Output directory (default: output)
- `-h` - Show help message

### After Installation

If installed, you can run:
```bash
fetch-pubmed -y 25 -s 1 -e 10 -o my_output
```

## Output Format

The script generates TSV files with the following columns:

1. **ID** - Unique identifier (format: `pubmed-dump-YYYY-NNNNNNNNNNNN`)
2. **Authors** - Comma-separated list of author last names
3. **Year** - Publication year
4. **Title** - Article title
5. **Abstract** - Article abstract text

All fields are:
- Quoted to handle special characters
- Tab-separated
- Sanitized (tabs, newlines, and quotes are escaped)

Output files are named `parsed_page_NNNN.tsv` and contain up to 100,000 records each.

## Project Structure

```
fetch-pubmed/
├── bin/
│   └── fetch-all.zsh      # Main fetching and processing script
├── libexec/
│   └── xml-to-tsv          # Perl script for XML to TSV conversion
├── Makefile                # Build and installation configuration
└── README.md              # This file
```

## How It Works

1. **Fetching**: The script generates URLs for PubMed baseline files (e.g., `pubmed25n0001.xml.gz`) and downloads them from NCBI's FTP server using `curl`.

2. **Streaming**: Files are downloaded, decompressed, and streamed directly to the parser without storing intermediate files.

3. **Parsing**: The Perl script (`xml-to-tsv`) processes the XML stream, extracting article metadata using regex patterns. It handles multiline text and extracts all authors from each article.

4. **Output**: Parsed data is written as TSV and automatically split into chunks using `gsplit` for easier handling of large datasets.

## Cleaning Up

Remove generated output files:
```bash
make clean
```

Uninstall the tool:
```bash
make uninstall
```

## License

MIT License

Copyright (c) 2025

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
