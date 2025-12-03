#!/bin/bash
# Dynamically detect BC version from environment variable or artifacts directory
# Returns the BC version number (e.g., "260" for BC 26.0, "270" for BC 27.1)

set -e

# Priority 1: Extract version from BC_ARTIFACT_URL if set
# Example URLs:
#   https://bcartifacts.azureedge.net/sandbox/26.0/w1
#   https://bcartifacts.azureedge.net/sandbox/25.0.20348.23013/us
#   https://bcartifacts.azureedge.net/onprem/27.0/w1
if [ -n "$BC_ARTIFACT_URL" ]; then
    # Extract version part from URL (e.g., "26.0" or "25.0.20348.23013")
    VERSION_PART=$(echo "$BC_ARTIFACT_URL" | grep -oP '/(sandbox|onprem)/\K[0-9]+\.[0-9]+(\.[0-9]+)*' | head -n 1)

    if [ -n "$VERSION_PART" ]; then
        # Extract major.minor (e.g., "26.0" from "26.0.20348.23013")
        MAJOR=$(echo "$VERSION_PART" | cut -d. -f1)
        MINOR=$(echo "$VERSION_PART" | cut -d. -f2)

        # Convert to 3-digit format (26.3 -> 260)
        echo "Detected BC version ${MAJOR}0 from BC_ARTIFACT_URL" >&2
        echo "${MAJOR}0"
        exit 0
    fi
fi

# Priority 2: Use BC_VERSION environment variable if set (available from compose.yml)
if [ -n "$BC_VERSION" ]; then
    # BC_VERSION can be in various formats:
    #   "26" or "25" (major only)
    #   "260" or "250" (already in 3-digit format)
    #   "26.0" or "25.3" (major.minor)
    #   "26.0.3" or "25.6.3.7" (full version format)

    # Extract major version (first number before any dot)
    MAJOR=$(echo "$BC_VERSION" | cut -d. -f1)

    # Validate it's a number
    if [[ "$MAJOR" =~ ^[0-9]+$ ]]; then
        # Check if already in 3-digit format (e.g., 260, 250)
        if [[ ${#MAJOR} -eq 3 ]]; then
            echo "Detected BC version $MAJOR from BC_VERSION environment variable (already in 3-digit format)" >&2
            echo "$MAJOR"
        else
            # Convert to 3-digit format by appending 0
            echo "Detected BC version ${MAJOR}0 from BC_VERSION environment variable" >&2
            echo "${MAJOR}0"
        fi
        exit 0
    else
        echo "WARNING: Invalid BC_VERSION format: $BC_VERSION" >&2
    fi
fi

# Priority 3: Fallback to detecting from artifacts directory (after installation)
# Check both possible folder names ("program files" for BC26-, "PFiles64" for BC27+)
for program_files_dir in "program files" "PFiles64"; do
    BC_ARTIFACTS_PATH="/home/bcartifacts/ServiceTier/$program_files_dir/Microsoft Dynamics NAV"

    if [ -d "$BC_ARTIFACTS_PATH" ]; then
        BC_VERSION_DIR=$(find "$BC_ARTIFACTS_PATH" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort -V | tail -n 1)

        if [ -n "$BC_VERSION_DIR" ]; then
            BC_VERSION_NUM=$(basename "$BC_VERSION_DIR")
            # Validate that it looks like a version number (should be numeric)
            if [[ "$BC_VERSION_NUM" =~ ^[0-9]+$ ]]; then
                echo "Detected BC version $BC_VERSION_NUM from artifacts directory" >&2
                echo "$BC_VERSION_NUM"
                exit 0
            fi
        fi
    fi
done
# Priority 4: Default fallback to BC 26.0
echo "WARNING: Could not detect BC version from any source, using default 260" >&2
echo "260"
