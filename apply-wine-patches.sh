#!/bin/bash

set -e

WINE_SRC_DIR="$1"
PATCHES_DIR="$2"

if [ -z "$WINE_SRC_DIR" ] || [ -z "$PATCHES_DIR" ]; then
    echo "Usage: $0 <wine-source-directory> <patches-directory>"
    exit 1
fi

if [ ! -d "$WINE_SRC_DIR" ]; then
    echo "ERROR: Wine source directory not found: $WINE_SRC_DIR"
    exit 1
fi

if [ ! -d "$PATCHES_DIR" ]; then
    echo "ERROR: Patches directory not found: $PATCHES_DIR"
    exit 1
fi

echo "Applying Wine patches from: $PATCHES_DIR"
echo "To Wine source at: $WINE_SRC_DIR"
echo

cd "$WINE_SRC_DIR"

# Track applied patches
APPLIED_PATCHES=""
FAILED_PATCHES=""

# Sort patches by name to ensure consistent order
# Patches with numeric prefixes (e.g., 001-) will be applied in order
for patch_file in $(find "$PATCHES_DIR" -name "*.patch" -type f | sort); do
    patch_name=$(basename "$patch_file")
    echo "Applying patch: $patch_name"
    
    # Try to apply the patch
    if patch -p1 --dry-run < "$patch_file" >/dev/null 2>&1; then
        # Dry run succeeded, apply for real
        if patch -p1 < "$patch_file"; then
            echo "  ✓ Successfully applied: $patch_name"
            APPLIED_PATCHES="$APPLIED_PATCHES$patch_name\n"
        else
            echo "  ✗ Failed to apply: $patch_name (but dry-run succeeded?)"
            FAILED_PATCHES="$FAILED_PATCHES$patch_name\n"
        fi
    else
        # Check if patch is already applied
        if patch -p1 -R --dry-run < "$patch_file" >/dev/null 2>&1; then
            echo "  ⚠ Patch already applied: $patch_name (skipping)"
            APPLIED_PATCHES="$APPLIED_PATCHES$patch_name (already applied)\n"
        else
            echo "  ✗ Failed to apply: $patch_name"
            echo "    Attempting with different patch levels..."
            
            # Try different patch levels
            applied=false
            for level in 0 2 3; do
                if patch -p$level --dry-run < "$patch_file" >/dev/null 2>&1; then
                    if patch -p$level < "$patch_file"; then
                        echo "    ✓ Successfully applied with -p$level"
                        APPLIED_PATCHES="$APPLIED_PATCHES$patch_name (with -p$level)\n"
                        applied=true
                        break
                    fi
                fi
            done
            
            if [ "$applied" = false ]; then
                echo "    ✗ Could not apply patch with any level"
                FAILED_PATCHES="$FAILED_PATCHES$patch_name\n"
            fi
        fi
    fi
    echo
done

# Summary
echo "========================================="
echo "Patch Application Summary"
echo "========================================="

if [ -n "$APPLIED_PATCHES" ]; then
    echo "Successfully applied patches:"
    echo -e "$APPLIED_PATCHES"
fi

if [ -n "$FAILED_PATCHES" ]; then
    echo "Failed patches:"
    echo -e "$FAILED_PATCHES"
    echo
    echo "WARNING: Some patches failed to apply!"
    echo "This may affect Wine functionality."
    # Don't exit with error - allow build to continue
fi

# Save patch application log
echo "Creating patch application log..."
{
    echo "Wine Patches Applied: $(date)"
    echo "=========================="
    echo
    if [ -n "$APPLIED_PATCHES" ]; then
        echo "Applied patches:"
        echo -e "$APPLIED_PATCHES"
    fi
    if [ -n "$FAILED_PATCHES" ]; then
        echo "Failed patches:"
        echo -e "$FAILED_PATCHES"
    fi
} > "$WINE_SRC_DIR/PATCHES_APPLIED.txt"

echo "Patch application complete!"