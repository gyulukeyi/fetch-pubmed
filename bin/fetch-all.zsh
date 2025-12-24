#!/bin/zsh

PROJECT_ROOT=${0:a:h:h} 

# Defaults
START=1
END=1274
YEAR=25
OUTPUT_DIR="output"

# Parse command line arguments
usage() { echo "Usage: $0 [-y year_no] [-s start_num] [-e end_num] [-o output_dir]"; exit 1; }

while getopts "y:s:e:o:h" opt; do
  case "${opt}" in
    y) YEAR=${OPTARG} ;;
    s) START=${OPTARG} ;;
    e) END=${OPTARG} ;;
    o) OUTPUT_DIR=${OPTARG} ;;
    h) usage ;;
    *) usage ;;
  esac
done

# Ensure output directory exists
mkdir -p "$OUTPUT_DIR"

# 1. Define the generator function
fetch_stream() {
  for ((i = START; i <= END; i++)); do
    fname=$(printf "pubmed%dn%04d.xml.gz" $YEAR $i)
    echo "Fetching: $fname..." >&2 
    curl -sS "https://ftp.ncbi.nlm.nih.gov/pubmed/baseline/$fname" | gunzip -c
  done
}

# 2. The Great Pipeline
echo "Processing PubMed files ${START} to ${END} into ${OUTPUT_DIR}/..." >&2

fetch_stream \
  | "$PROJECT_ROOT/libexec/xml-to-tsv" \
  | gsplit -l 100000 -d --additional-suffix=.tsv - "${OUTPUT_DIR}/parsed_page_"
