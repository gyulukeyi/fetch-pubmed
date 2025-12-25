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
    
    # Fetch with explicit error checking and retry logic
    # -f: fail on HTTP errors (returns non-zero exit code for 4xx/5xx)
    # -S: show errors even in silent mode  
    # --connect-timeout: timeout for initial connection (30 seconds)
    # --max-time: prevent hanging (10 minutes per file, increased for large files)
    # --retry: retry on transient failures (5 retries with exponential backoff)
    # --retry-delay: initial delay between retries (2 seconds)
    # --retry-max-time: maximum time to spend retrying (20 minutes total)
    # --retry-connrefused: retry even on connection refused errors
    # --show-error: show error messages even with -s
    # --speed-time: consider transfer stalled if speed below --speed-limit for this duration
    # --speed-limit: minimum transfer speed in bytes/sec (1KB/s)
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
    
    # Retry logic for specific error codes (18 = partial file, 23 = write error)
    local max_attempts=3
    local attempt=1
    local curl_exit=1
    local gunzip_failed=0
    
    while [[ $attempt -le $max_attempts ]]; do
      if [[ $attempt -gt 1 ]]; then
        # Exponential backoff: 2^attempt seconds (2, 4, 8 seconds)
        local backoff=$((2 ** attempt))
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Retry attempt $attempt/$max_attempts for $fname (waiting ${backoff}s)..." >&2
        sleep $backoff
      fi
      
      # Start curl in background, writing to pipe
      # Note: stderr (errors) will be visible due to -S flag, stdout goes to pipe (for gunzip)
      (curl -f -sS \
        --connect-timeout 30 \
        --max-time 600 \
        --retry 5 \
        --retry-delay 2 \
        --retry-max-time 1200 \
        --retry-connrefused \
        --speed-time 60 \
        --speed-limit 1024 \
        --show-error \
        "$url" > "$pipe" 2>&1; echo $? > "$exit_file") &
      local curl_pid=$!
      
      # Stream through gunzip (this will block until curl finishes or pipe closes)
      # Capture gunzip stderr to show errors if decompression fails
      local gunzip_stderr=$(mktemp)
      gunzip_failed=0
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
      curl_exit=$(cat "$exit_file" 2>/dev/null || echo "1")
      
      # Check if we should retry
      # Exit codes to retry: 18 (partial file), 23 (write error), 28 (timeout), 35 (SSL connect error)
      if [[ $curl_exit -eq 0 ]] && [[ $gunzip_failed -eq 0 ]]; then
        # Success!
        break
      elif [[ $attempt -lt $max_attempts ]] && [[ $curl_exit -eq 18 || $curl_exit -eq 23 || $curl_exit -eq 28 || $curl_exit -eq 35 ]]; then
        # Retry on specific error codes
        echo "Error: curl exit code $curl_exit for $fname, will retry..." >&2
        attempt=$((attempt + 1))
        # Recreate pipe for next attempt
        rm -f "$pipe" "$exit_file"
        mkfifo "$pipe" 2>/dev/null || {
          echo "Error: Failed to recreate pipe for $fname" >&2
          break
        }
        continue
      else
        # Final failure or non-retryable error
        break
      fi
    done
    
    # Cleanup pipes
    rm -f "$pipe" "$exit_file"
    
    # Check if everything succeeded
    if [[ $curl_exit -eq 0 ]] && [[ $gunzip_failed -eq 0 ]]; then
      success_count=$((success_count + 1))
    else
      if [[ $curl_exit -ne 0 ]]; then
        echo "Error: Failed to fetch $fname after $attempt attempt(s) (curl exit code: $curl_exit)" >&2
        # Provide helpful error messages for common exit codes
        case $curl_exit in
          18) echo "  -> Partial file transfer (connection interrupted)" >&2 ;;
          23) echo "  -> Write error (possible pipe/filesystem issue)" >&2 ;;
          28) echo "  -> Operation timeout" >&2 ;;
          35) echo "  -> SSL/TLS connection error" >&2 ;;
        esac
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
