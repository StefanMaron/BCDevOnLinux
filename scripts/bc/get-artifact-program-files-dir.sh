#!/bin/bash
# Helper script to get the correct BC artifact "program files" directory path
# Handles both "program files" (BC26-) and "PFiles64" (BC27+) naming conventions
#
# Usage: get-artifact-program-files-dir.sh [base_path]
#   base_path: Optional. Base path to artifacts (default: /home/bcartifacts)
#
# Returns: Full path to the "program files" (or "PFiles64") directory

set -e

# Get base path from parameter or use default
BASE_PATH="${1:-/home/bcartifacts}"

# Get BC version
BC_VERSION=$(/home/scripts/bc/detect-bc-version.sh 2>/dev/null)
if [ $? -ne 0 ] || [ -z "$BC_VERSION" ]; then
    echo "ERROR: Failed to detect BC version" >&2
    exit 1
fi

# Base path for BC artifacts
BC_ARTIFACTS_BASE="$BASE_PATH/ServiceTier"

# Try both possible folder names
for program_files_dir in "program files" "PFiles64"; do
    CANDIDATE="$BC_ARTIFACTS_BASE/$program_files_dir"
    if [ -d "$CANDIDATE" ]; then
        echo "$CANDIDATE"
        exit 0
    fi
done

# If we get here, path was not found
echo "ERROR: BC artifact program files directory not found" >&2
echo "Searched in:" >&2
echo "  $BC_ARTIFACTS_BASE/program files" >&2
echo "  $BC_ARTIFACTS_BASE/PFiles64" >&2
exit 1
