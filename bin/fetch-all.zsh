#!/bin/zsh
# Copyright (c) 2025 Gyu-min Lee. Licensed under the MIT License.

PROJECT_ROOT=${0:a:h:h} 

# Defaults
START=1
END=1274
YEAR=25
OUTPUT_DIR="output"
LOG_FILE=""

# Parse command line arguments
usage() { 
  echo "Usage: $(basename $0) [-y year_no] [-s start_num] [-e end_num] [-o output_dir] [-l log_file]"
  exit 1
}

while getopts "y:s:e:o:l:h" opt; do
  case "${opt}" in
    y) YEAR=${OPTARG} ;;
    s) START=${OPTARG} ;;
    e) END=${OPTARG} ;;
    o) OUTPUT_DIR=${OPTARG} ;;
    l) LOG_FILE=${OPTARG} ;;
    h) usage ;;
    *) usage ;;
  esac
done

# Ensure output directory exists
if ! mkdir -p "$OUTPUT_DIR"; then
  echo "Error: Failed to create output directory: $OUTPUT_DIR" >&2
  exit 1
fi

# --- LOGGING SETUP ---
if [[ -n "$LOG_FILE" ]]; then
  # 1. Initialize the log file (clear it or create it)
  : > "$LOG_FILE"
  # 2. The Zsh Magic:
  # Redirect FD 2 (Stderr) into a process substitution that runs 'tee'.
  # 'tee' writes to the file AND writes back to the original stderr (>dev/tty).
  exec 2> >(tee -a "$LOG_FILE" >&2)
  echo "Logging enabled: writing to $LOG_FILE" >&2
fi
# ---------------------

# Check if required commands exist
for cmd in curl gunzip gsplit; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Error: Required command '$cmd' not found in PATH" >&2
    exit 1
  fi
done

# Check if xml-to-tsv exists and is executable
if [[ ! -x "$PROJECT_ROOT/libexec/xml-to-tsv" ]]; then
  echo "Error: xml-to-tsv script not found or not executable: $PROJECT_ROOT/libexec/xml-to-tsv" >&2
  exit 1
fi

# Track failures (using a temp file since we're in a pipeline)
FAILED_LOG=$(mktemp)
trap "rm -f '$FAILED_LOG'" EXIT

# 1. Define the generator function
fetch_stream() {
  local success_count=0
  local fail_count=0
  
  # Create a temporary directory for downloads to avoid partial pipe writes
  local tmp_dir=$(mktemp -d)
  
  # Cleanup temp dir on function return/exit
  trap "rm -rf '$tmp_dir'" RETURN EXIT

  for ((i = START; i <= END; i++)); do
    fname=$(printf "pubmed%dn%04d.xml.gz" $YEAR $i)
    url="https://ftp.ncbi.nlm.nih.gov/pubmed/baseline/$fname"
    tmp_file="$tmp_dir/$fname"
    
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Fetching: $fname..." >&2 
    
    local max_attempts=3
    local attempt=1
    local success=0
    
    while [[ $attempt -le $max_attempts ]]; do
      if [[ $attempt -gt 1 ]]; then
        local backoff=$((2 ** attempt))
        echo "Retry attempt $attempt/$max_attempts for $fname (waiting ${backoff}s)..." >&2
        sleep $backoff
      fi
      
      # Download to a temporary file first!
      # This prevents partial data from being sent to xml-to-tsv.
      if curl -f -sS \
        --connect-timeout 30 \
        --max-time 600 \
        --retry 5 \
        --retry-delay 2 \
        --retry-max-time 1200 \
        --retry-connrefused \
        --speed-time 60 \
        --speed-limit 1024 \
        --show-error \
        -o "$tmp_file" \
        "$url"; then
        
        # Validation: Check if the downloaded file is a valid gzip
        if gunzip -t "$tmp_file" 2>/dev/null; then
          # Success! Stream it to stdout (the pipeline)
          gunzip -c "$tmp_file"
          success=1
          rm -f "$tmp_file"
          break
        else
          echo "Error: Downloaded file $fname is corrupted (gzip check failed)." >&2
        fi
      else
        echo "Error: curl failed for $fname (attempt $attempt)" >&2
      fi
      
      attempt=$((attempt + 1))
    done
    
    if [[ $success -eq 1 ]]; then
      success_count=$((success_count + 1))
    else
      echo "Error: Failed to fetch $fname after 3 attempts." >&2
      echo "$fname" >> "$FAILED_LOG"
      fail_count=$((fail_count + 1))
    fi
  done
  
  echo "Completed: $success_count succeeded, $fail_count failed" >&2
}

# 2. The Great Pipeline
echo "Processing PubMed${YEAR} files ${START} to ${END} into ${OUTPUT_DIR}/..." >&2

PIPELINE_EXIT=0
# Added -a 4 to gsplit to ensure 4-digit suffixes (0000-9999) and avoid the 9000 jump
fetch_stream | "$PROJECT_ROOT/libexec/xml-to-tsv" | gsplit -l 100000 -d -a 4 --additional-suffix=.tsv - "${OUTPUT_DIR}/parsed_page_" || PIPELINE_EXIT=$?

echo "" >&2
if [[ -s "$FAILED_LOG" ]]; then
  local failed_count=$(wc -l < "$FAILED_LOG" | tr -d ' ')
  echo "WARNING: $failed_count file(s) failed to download:" >&2
  cat "$FAILED_LOG" >&2
  echo "" >&2
fi

if [[ $PIPELINE_EXIT -ne 0 ]]; then
  echo "Error: Pipeline failed with exit code $PIPELINE_EXIT" >&2
  exit $PIPELINE_EXIT
else
  echo "Processing complete!" >&2
fi
