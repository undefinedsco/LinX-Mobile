#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
APPLE_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)"

WHISPER_VERSION="v1.8.4"
MODEL_FILE="ggml-base.bin"
MODEL_URL="https://huggingface.co/ggerganov/whisper.cpp/resolve/main/${MODEL_FILE}"
MODEL_SHA256="60ed5bc3dd14eea856493d334349b405782ddcaf0028d4b5df4088345fba2efe"
MODEL_SIZE_BYTES="147951465"

XCF_ZIP="whisper-${WHISPER_VERSION}-xcframework.zip"
XCF_URL="https://github.com/ggml-org/whisper.cpp/releases/download/${WHISPER_VERSION}/${XCF_ZIP}"
XCF_SHA256="1c7a93bd20fe4e57e0af12051ddb34b7a434dfc9acc02c8313393150b6d1821f"

MODEL_DIR="$APPLE_DIR/LinXApple/Resources/WhisperModels"
MODEL_PATH="$MODEL_DIR/$MODEL_FILE"
VENDOR_DIR="$APPLE_DIR/Vendors/Whisper"
XCF_PATH="$VENDOR_DIR/whisper.xcframework"
CACHE_DIR="${LINX_WHISPER_CACHE_DIR:-$APPLE_DIR/.build/whisper}"

log() {
    printf '%s\n' "$*"
}

sha256() {
    shasum -a 256 "$1" | awk '{print $1}'
}

file_size() {
    wc -c < "$1" | tr -d ' '
}

validate_checksum() {
    local file="$1"
    local expected="$2"

    [[ -f "$file" ]] && [[ "$(sha256 "$file")" == "$expected" ]]
}

validate_size() {
    local file="$1"
    local expected="$2"

    [[ -f "$file" ]] && [[ "$(file_size "$file")" == "$expected" ]]
}

download() {
    local url="$1"
    local output="$2"
    local partial="${output}.partial"

    rm -f "$partial"
    curl -L --fail --retry 3 --output "$partial" "$url"
    mv "$partial" "$output"
}

ensure_model() {
    mkdir -p "$MODEL_DIR" "$CACHE_DIR"

    if validate_checksum "$MODEL_PATH" "$MODEL_SHA256" && validate_size "$MODEL_PATH" "$MODEL_SIZE_BYTES"; then
        log "Model already ready: $MODEL_PATH"
        return
    fi

    local cached="$CACHE_DIR/$MODEL_FILE"
    if ! validate_checksum "$cached" "$MODEL_SHA256" || ! validate_size "$cached" "$MODEL_SIZE_BYTES"; then
        log "Downloading $MODEL_FILE..."
        download "$MODEL_URL" "$cached"
    fi

    if ! validate_checksum "$cached" "$MODEL_SHA256"; then
        log "Checksum mismatch for $cached"
        exit 1
    fi

    if ! validate_size "$cached" "$MODEL_SIZE_BYTES"; then
        log "Unexpected size for $cached"
        exit 1
    fi

    install -m 0644 "$cached" "$MODEL_PATH"
    log "Installed model: $MODEL_PATH"
}

valid_xcframework() {
    local path="$1"

    [[ -f "$path/Info.plist" ]] &&
        [[ -f "$path/ios-arm64/whisper.framework/whisper" ]] &&
        [[ -f "$path/ios-arm64/whisper.framework/Modules/module.modulemap" ]] &&
        [[ -f "$path/ios-arm64_x86_64-simulator/whisper.framework/whisper" ]] &&
        [[ -f "$path/ios-arm64_x86_64-simulator/whisper.framework/Modules/module.modulemap" ]]
}

ensure_xcframework() {
    mkdir -p "$VENDOR_DIR" "$CACHE_DIR"

    if valid_xcframework "$XCF_PATH"; then
        log "XCFramework already ready: $XCF_PATH"
        return
    fi

    local cached="$CACHE_DIR/$XCF_ZIP"
    if ! validate_checksum "$cached" "$XCF_SHA256"; then
        log "Downloading $XCF_ZIP..."
        download "$XCF_URL" "$cached"
    fi

    if ! validate_checksum "$cached" "$XCF_SHA256"; then
        log "Checksum mismatch for $cached"
        exit 1
    fi

    local extract_dir
    extract_dir="$(mktemp -d "${TMPDIR:-/tmp}/linx-whisper-xcf.XXXXXX")"
    trap 'rm -rf "$extract_dir"' RETURN

    unzip -q "$cached" -d "$extract_dir"

    local extracted="$extract_dir/build-apple/whisper.xcframework"
    if ! valid_xcframework "$extracted"; then
        log "Downloaded archive does not contain the expected iOS whisper.xcframework"
        exit 1
    fi

    rm -rf "$XCF_PATH"
    cp -R "$extracted" "$XCF_PATH"
    log "Installed XCFramework: $XCF_PATH"
}

ensure_model
ensure_xcframework

log "Whisper artifacts are ready."
