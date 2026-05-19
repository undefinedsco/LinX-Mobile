#!/bin/sh
set -eu

if [ "${ACTION:-}" != "install" ] || [ "${PLATFORM_NAME:-}" != "iphoneos" ]; then
  exit 0
fi

if [ "${SKIP_INSTALL:-}" = "YES" ]; then
  exit 0
fi

framework_binary="${BUILT_PRODUCTS_DIR:-}/GiphyUISDK.framework/GiphyUISDK"
if [ ! -f "$framework_binary" ]; then
  framework_binary="${TARGET_BUILD_DIR:-}/${FRAMEWORKS_FOLDER_PATH:-Frameworks}/GiphyUISDK.framework/GiphyUISDK"
fi

if [ ! -f "$framework_binary" ]; then
  echo "warning: GiphyUISDK.framework binary was not found; skipping dSYM generation"
  exit 0
fi

if ! command -v dsymutil >/dev/null 2>&1; then
  echo "error: dsymutil is required to generate GiphyUISDK.framework.dSYM"
  exit 1
fi

if ! command -v dwarfdump >/dev/null 2>&1; then
  echo "error: dwarfdump is required to verify GiphyUISDK.framework.dSYM"
  exit 1
fi

dsym_folder="${DWARF_DSYM_FOLDER_PATH:-}"
if [ -z "$dsym_folder" ]; then
  echo "error: DWARF_DSYM_FOLDER_PATH is not set; cannot place GiphyUISDK.framework.dSYM"
  exit 1
fi

output_dsym="${dsym_folder}/GiphyUISDK.framework.dSYM"
rm -rf "$output_dsym"
mkdir -p "$dsym_folder"
dsymutil "$framework_binary" -o "$output_dsym"

framework_uuids="$(dwarfdump --uuid "$framework_binary" | awk '{ print $2 }')"
for uuid in $framework_uuids; do
  if ! dwarfdump --uuid "$output_dsym" | grep -q "$uuid"; then
    echo "error: generated GiphyUISDK.framework.dSYM is missing UUID ${uuid}"
    exit 1
  fi
done

if [ -n "${ARCHIVE_DSYMS_PATH:-}" ] && [ "$ARCHIVE_DSYMS_PATH" != "$dsym_folder" ]; then
  mkdir -p "$ARCHIVE_DSYMS_PATH"
  rm -rf "${ARCHIVE_DSYMS_PATH}/GiphyUISDK.framework.dSYM"
  cp -R "$output_dsym" "$ARCHIVE_DSYMS_PATH/"
fi

echo "Generated GiphyUISDK.framework.dSYM at ${output_dsym}"
