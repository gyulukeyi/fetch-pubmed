#!/bin/zsh
# Copyright (c) 2025 Gyu-min Lee. Licensed under the MIT License.

PROJECT_ROOT=${0:a:h:h} 

# Defaults
START=1
END=1274
YEAR=25
OUTPUT_DIR="output"
LOG_FILE=""  # New variable for log file

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
    l) LOG_FILE=${OPTARG} ;;  # Capture log file path
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

# 1. Define the generator function with error handling
fetch_stream() {
  local success_count=0
  local fail_count=0
  
  for ((i = START; i <= END; i++)); do
    fname=$(printf "pubmed%dn%04d.xml.gz" $YEAR $i)
    url="https://ftp.ncbi.nlm.nih.gov/pubmed/baseline/$fname"
    
    # Add a timestamp to the log for better debugging
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Fetching: $fname..." >&2 
    
    # Fetch with explicit error checking
    # -f: fail on HTTP errors (returns non-zero exit code for 4xx/5xx)
    # -S: show errors even in silent mode  
    # --max-time: prevent hanging (5 minutes per file)
    # --retry: retry on transient failures (3 retries with 5 second delay)
    # --show-error: show error messages even with -s
    #
    # Use a named pipe (FIFO) to stream while checking exit status
    local pipe=$(mktemp -u)
    local exit_file=$(mktemp)
    mkfifo "$pipe" 2>/dev/null || {
      echo "Error: Failed to create pipe for $fname" >&2
      echo "$fname" >> "$FAILED_LOG"
      fail_count=$((fail_count + 1))
      continue
    }
    
    # Start curl in background, writing to pipe
    # Note: stderr (errors) will be visible due to -S flag, stdout goes to pipe (for gunzip)
    (curl -f -sS --max-time 300 --retry 3 --retry-delay 5 --show-error "$url" > "$pipe"; echo $? > "$exit_file") &
    local curl_pid=$!
    
    # Stream through gunzip (this will block until curl finishes or pipe closes)
    # Capture gunzip stderr to show errors if decompression fails
    local gunzip_stderr=$(mktemp)
    local gunzip_failed=0
    if ! gunzip -c < "$pipe" 2> "$gunzip_stderr"; then
      gunzip_failed=1
      # Show gunzip errors if any
      if [[ -s "$gunzip_stderr" ]]; then
        echo "gunzip error for $fname:" >&2
        cat "$gunzip_stderr" >&2
      fi
    fi
    rm -f "$gunzip_stderr"
    
    # Wait for curl and check its exit status
    wait $curl_pid 2>/dev/null
    local curl_exit=$(cat "$exit_file" 2>/dev/null || echo "1")
    
    # Cleanup pipes
    rm -f "$pipe" "$exit_file"
    
    # Check if everything succeeded
    if [[ $curl_exit -eq 0 ]] && [[ $gunzip_failed -eq 0 ]]; then
      success_count=$((success_count + 1))
    else
      if [[ $curl_exit -ne 0 ]]; then
        echo "Error: Failed to fetch $fname (curl exit code: $curl_exit)" >&2
      fi
      if [[ $gunzip_failed -ne 0 ]]; then
        echo "Error: Failed to decompress $fname" >&2
      fi
      echo "$fname" >> "$FAILED_LOG"
      fail_count=$((fail_count + 1))
    fi
  done
  
  # Report progress to stderr
  echo "Completed: $success_count succeeded, $fail_count failed" >&2
}

# 2. The Great Pipeline
echo "Processing PubMed${YEAR} files ${START} to ${END} into ${OUTPUT_DIR}/..." >&2

# Run the pipeline and capture its exit status
PIPELINE_EXIT=0
fetch_stream | "$PROJECT_ROOT/libexec/xml-to-tsv" | gsplit -l 100000 -d --additional-suffix=.tsv - "${OUTPUT_DIR}/parsed_page_" || PIPELINE_EXIT=$?

# Report results
echo "" >&2
if [[ -s "$FAILED_LOG" ]]; then
  local failed_count=$(wc -l < "$FAILED_LOG" | tr -d ' ')
  echo "WARNING: $failed_count file(s) failed to download:" >&2
  while IFS= read -r fname; do
    echo "  - $fname" >&2
  done < "$FAILED_LOG"
  echo "" >&2
fi

if [[ $PIPELINE_EXIT -ne 0 ]]; then
  echo "Error: Pipeline failed with exit code $PIPELINE_EXIT" >&2
  exit $PIPELINE_EXIT
else
  echo "Processing complete!" >&2
fi
