# Wine Patches Directory

This directory contains custom patches that are automatically applied to Wine during the build process.

## How it works

All `.patch` files in this directory will be automatically applied to the Wine source code during the Docker build. The patches are applied after Wine Staging patches but before Wine is compiled.

## Adding new patches

1. Create your patch file against the Wine source code
2. Name it with a `.patch` extension
3. Optionally prefix with a number for ordering (e.g., `001-myfix.patch`, `002-another.patch`)
4. Place it in this directory
5. Rebuild the container with `./build-wine-custom.sh`

## Disabling patches

To disable a patch without deleting it, rename it with a `.disabled` extension:
```bash
mv problematic-patch.patch problematic-patch.patch.disabled
```

## Patch naming convention

- Use descriptive names: `wine-locale-display-fix.patch`
- For ordered application, use numeric prefixes: `001-critical-fix.patch`
- Patches are applied in alphabetical order (so 001 comes before 002, etc.)

## Current patches

### Active patches

#### 001-wine-locale-display-fix.patch
Fixes the issue where Wine's `LocaleNameToLCID("en-US")` returns 0 instead of the correct value (0x0409). This patch is essential for Business Central to properly initialize its culture/language support.

### Obsolete patches (disabled)

Files with `.disabled` extension are ignored by the patch system:

- `OBSOLETE-wine-locale-fix.patch.disabled` - Earlier attempt at locale fix (superseded by 001-wine-locale-display-fix.patch)
- `OBSOLETE-wine-locale-debug.patch.disabled` - Debug patches for locale issues (no longer needed)

## Troubleshooting

If a patch fails to apply:
1. Check `/opt/wine-custom/PATCHES_APPLIED.txt` in the container for details
2. The build will continue even if some patches fail
3. Failed patches are logged but don't stop the build process

## Creating patches

To create a new patch:
```bash
# Clone Wine source
git clone https://gitlab.winehq.org/wine/wine.git
cd wine

# Make your changes
vim dlls/kernelbase/locale.c

# Create the patch
git diff > ../my-new-fix.patch

# Copy to wine-patches directory
cp ../my-new-fix.patch /path/to/BCDevOnLinux/wine-patches/
```

## Patch application log

After building, you can check which patches were applied:
```bash
docker exec bcdevonlinux-bc-1 cat /opt/wine-custom/PATCHES_APPLIED.txt
```