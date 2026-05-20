#!/bin/sh
set -eu

error() {
  echo "error: $*" >&2
  exit 1
}

usage() {
  cat <<'USAGE'
Usage: ./scripts/release-ios.sh <command>

Commands:
  doctor              Check asc, xcodebuild, plutil, and asc authentication
  prepare             Prepare generated project files and local Whisper artifacts
  build               Build the LinXApple app locally
  test                Run the native app test suite
  validate            Validate workflow syntax and App Store Connect release readiness
  preflight           Run doctor, tests, and App Store Connect validation
  dry-run-testflight  Rehearse TestFlight archive/export/upload workflow
  release-testflight  Run preflight, then upload and distribute to TestFlight
  dry-run-appstore    Rehearse App Store archive/export/submission workflow
  release-appstore    Run preflight, then upload and submit for App Store review
  testflight          Archive, export, upload, and distribute to TestFlight
  appstore            Archive, export, upload, and submit for App Store review
  status              Show App Store Connect release status
  logs                Tail the latest local build/test log
  clean               Remove generated release artifacts, reports, and logs

Required environment:
  ASC_APP_ID or APP_ID   App Store Connect app ID for validate/release/status
  VERSION               Marketing version for validate/release commands
  TESTFLIGHT_GROUP      TestFlight group for TestFlight release commands

Safety:
  CONFIRM=1 is required for testflight/appstore/release/clean unless DRY_RUN=1.

Common examples:
  ./scripts/release-ios.sh build
  ./scripts/release-ios.sh test
  VERSION=0.1.1 ASC_APP_ID=123456789 ./scripts/release-ios.sh preflight
  DRY_RUN=1 VERSION=0.1.1 ASC_APP_ID=123456789 TESTFLIGHT_GROUP="External Testers" ./scripts/release-ios.sh dry-run-testflight
  CONFIRM=1 VERSION=0.1.1 ASC_APP_ID=123456789 TESTFLIGHT_GROUP="External Testers" ./scripts/release-ios.sh release-testflight
  CONFIRM=1 VERSION=0.1.1 ASC_APP_ID=123456789 ./scripts/release-ios.sh release-appstore
USAGE
}

log() {
  printf '%s\n' "$*"
}

require_tool() {
  command -v "$1" >/dev/null 2>&1 || error "$1 is not installed or not on PATH"
}

ensure_dir() {
  mkdir -p "$1"
}

run_id() {
  date -u +%Y%m%dT%H%M%SZ
}

run_logged() {
  log_path="$1"
  shift

  ensure_dir "$(dirname -- "$log_path")"
  log "Writing log: $log_path"

  set +e
  "$@" >"$log_path" 2>&1
  status=$?
  set -e

  if [ "$status" -ne 0 ]; then
    echo "error: command failed with exit $status: $*" >&2
    echo "error: latest log: $log_path" >&2
    echo "error: last 60 log lines:" >&2
    tail -60 "$log_path" >&2 || true
    exit "$status"
  fi
}

asc_run() {
  if [ -n "${ASC_PROFILE:-}" ]; then
    asc --profile "$ASC_PROFILE" "$@"
  else
    asc "$@"
  fi
}

require_app_id() {
  APP_ID_VALUE="${ASC_APP_ID:-${APP_ID:-}}"
  [ -n "$APP_ID_VALUE" ] || error "ASC_APP_ID or APP_ID is required"
}

require_version() {
  [ -n "${VERSION:-}" ] || error "VERSION is required"
}

require_confirmed_mutation() {
  if [ "${DRY_RUN:-0}" = "1" ]; then
    return 0
  fi
  [ "${CONFIRM:-0}" = "1" ] || error "CONFIRM=1 is required for this command"
}

require_testflight_group() {
  [ -n "${TESTFLIGHT_GROUP:-}" ] || error "TESTFLIGHT_GROUP is required"
}

require_asc_tools() {
  require_tool asc
  require_tool xcodebuild
  require_tool plutil
}

project_file_path() {
  printf '%s/project.pbxproj\n' "$PROJECT_PATH"
}

ensure_project_generated() {
  [ -f project.yml ] || error "project.yml is missing"

  pbxproj_path="$(project_file_path)"
  needs_generate=0

  if [ "${FORCE_XCODEGEN:-0}" = "1" ]; then
    needs_generate=1
  elif [ ! -f "$pbxproj_path" ]; then
    needs_generate=1
  elif [ project.yml -nt "$pbxproj_path" ]; then
    needs_generate=1
  fi

  if [ "$needs_generate" = "1" ]; then
    require_tool xcodegen
    log "Regenerating $PROJECT_PATH from project.yml..."
    run_logged "$RUNS_DIR/xcodegen-$RUN_ID.log" xcodegen generate --spec project.yml
  else
    log "$PROJECT_PATH is up to date."
  fi
}

whisper_artifacts_ready() {
  [ -s LinXApple/Resources/WhisperModels/ggml-base.bin ] && \
    [ -f Vendors/Whisper/whisper.xcframework/Info.plist ] && \
    [ -f Vendors/Whisper/whisper.xcframework/ios-arm64/whisper.framework/whisper ] && \
    [ -f Vendors/Whisper/whisper.xcframework/ios-arm64_x86_64-simulator/whisper.framework/whisper ]
}

ensure_whisper_artifacts() {
  if whisper_artifacts_ready; then
    log "Whisper artifacts are ready."
    return 0
  fi

  [ "${SKIP_WHISPER_PREPARE:-0}" != "1" ] || error "Whisper artifacts are missing and SKIP_WHISPER_PREPARE=1 was set"

  require_tool bash
  require_tool curl
  require_tool shasum
  require_tool unzip

  log "Preparing Whisper artifacts..."
  bash scripts/prepare-whisper.sh
}

run_prepare() {
  ensure_dir "$ARTIFACTS_DIR"
  ensure_dir "$REPORTS_DIR"
  ensure_dir "$RUNS_DIR"
  ensure_project_generated
  ensure_whisper_artifacts
}

resolve_packages() {
  require_tool xcodebuild
  run_logged \
    "$RUNS_DIR/resolve-packages-$RUN_ID.log" \
    xcodebuild \
      -resolvePackageDependencies \
      -project "$PROJECT_PATH" \
      -scheme "$SCHEME"
}

run_build() {
  run_prepare
  resolve_packages
  require_tool xcodebuild
  run_logged \
    "$RUNS_DIR/build-$RUN_ID.log" \
    xcodebuild \
      build \
      -project "$PROJECT_PATH" \
      -scheme "$SCHEME" \
      -configuration "$CONFIGURATION" \
      -destination "$BUILD_DESTINATION" \
      -allowProvisioningUpdates
  log "Build succeeded for $SCHEME ($CONFIGURATION)."
}

run_tests() {
  run_prepare
  resolve_packages
  require_tool xcodebuild

  result_bundle="$REPORTS_DIR/tests-$RUN_ID.xcresult"
  rm -rf "$result_bundle"

  run_logged \
    "$RUNS_DIR/test-$RUN_ID.log" \
    xcodebuild \
      test \
      -project "$PROJECT_PATH" \
      -scheme "$SCHEME" \
      -configuration "$TEST_CONFIGURATION" \
      -destination "$TEST_DESTINATION" \
      -resultBundlePath "$result_bundle"
  log "Tests succeeded for $SCHEME. Result bundle: $result_bundle"
}

run_doctor() {
  require_asc_tools
  asc_run auth status --validate
  asc_run auth doctor
}

run_validate() {
  require_app_id
  require_version
  require_asc_tools
  asc_run workflow validate --file .asc/workflow.json
  asc_run validate --app "$APP_ID_VALUE" --version "$VERSION" --platform IOS --output table
}

run_preflight() {
  require_app_id
  require_version
  run_doctor

  if [ "${SKIP_TESTS:-0}" = "1" ]; then
    log "Skipping tests because SKIP_TESTS=1."
    run_prepare
  else
    run_tests
  fi

  run_validate
}

run_workflow() {
  workflow_name="$1"
  shift

  if [ "${DRY_RUN:-0}" = "1" ]; then
    asc_run workflow run --file .asc/workflow.json --dry-run "$workflow_name" "$@"
  else
    asc_run workflow run --file .asc/workflow.json "$workflow_name" "$@"
  fi
}

run_testflight_workflow() {
  require_app_id
  require_version
  require_testflight_group
  require_confirmed_mutation
  require_asc_tools
  run_workflow \
    testflight_beta \
    "APP_ID:$APP_ID_VALUE" \
    "VERSION:$VERSION" \
    "TESTFLIGHT_GROUP:$TESTFLIGHT_GROUP" \
    "SUBMIT_BETA_REVIEW:${SUBMIT_BETA_REVIEW:-0}" \
    "CONFIRM:${CONFIRM:-0}" \
    "PROJECT_PATH:$PROJECT_PATH" \
    "SCHEME:$SCHEME" \
    "CONFIGURATION:$CONFIGURATION" \
    "ARTIFACTS_DIR:$ARTIFACTS_DIR" \
    "REPORTS_DIR:$REPORTS_DIR"
}

run_appstore_workflow() {
  require_app_id
  require_version
  require_confirmed_mutation
  require_asc_tools
  run_workflow \
    appstore_release \
    "APP_ID:$APP_ID_VALUE" \
    "VERSION:$VERSION" \
    "CONFIRM:${CONFIRM:-0}" \
    "PROJECT_PATH:$PROJECT_PATH" \
    "SCHEME:$SCHEME" \
    "CONFIGURATION:$CONFIGURATION" \
    "ARTIFACTS_DIR:$ARTIFACTS_DIR" \
    "REPORTS_DIR:$REPORTS_DIR"
}

run_dry_run_testflight() {
  DRY_RUN=1
  run_testflight_workflow
}

run_release_testflight() {
  require_app_id
  require_version
  require_testflight_group
  require_confirmed_mutation
  run_preflight
  run_testflight_workflow
}

run_dry_run_appstore() {
  DRY_RUN=1
  run_appstore_workflow
}

run_release_appstore() {
  require_app_id
  require_version
  require_confirmed_mutation
  run_preflight
  run_appstore_workflow
}

run_status() {
  require_app_id
  require_asc_tools
  asc_run status --app "$APP_ID_VALUE" --output table
}

latest_log_file() {
  find "$RUNS_DIR" "$REPORTS_DIR" -type f -name '*.log' -print 2>/dev/null | while IFS= read -r file_path; do
    printf '%s\t%s\n' "$(stat -f '%m' "$file_path")" "$file_path"
  done | sort -rn | sed -n '1s/^[^[:space:]]*[[:space:]]//p'
}

run_logs() {
  ensure_dir "$RUNS_DIR"
  ensure_dir "$REPORTS_DIR"

  if [ -n "${LOG_FILE:-}" ]; then
    [ -f "$LOG_FILE" ] || error "LOG_FILE does not exist: $LOG_FILE"
    latest="$LOG_FILE"
  else
    latest="$(latest_log_file)"
    [ -n "$latest" ] || error "No .log files found under $RUNS_DIR or $REPORTS_DIR"
  fi

  log "Latest log: $latest"
  tail -80 "$latest"
}

run_clean() {
  [ "${CONFIRM:-0}" = "1" ] || error "CONFIRM=1 is required for clean"
  rm -rf "$ARTIFACTS_DIR" "$REPORTS_DIR" "$RUNS_DIR"
  log "Removed $ARTIFACTS_DIR, $REPORTS_DIR, and $RUNS_DIR."
}

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
APPLE_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
cd "$APPLE_DIR"

PROJECT_PATH="${PROJECT_PATH:-LinXApple.xcodeproj}"
SCHEME="${SCHEME:-LinXApple}"
CONFIGURATION="${CONFIGURATION:-Release}"
TEST_CONFIGURATION="${TEST_CONFIGURATION:-Debug}"
BUILD_DESTINATION="${BUILD_DESTINATION:-generic/platform=iOS}"
TEST_DESTINATION="${DESTINATION:-platform=iOS Simulator,name=iPhone 16}"
ARTIFACTS_DIR="${ARTIFACTS_DIR:-.asc/artifacts}"
REPORTS_DIR="${REPORTS_DIR:-.asc/reports}"
RUNS_DIR="${RUNS_DIR:-.asc/runs}"
RUN_ID="${RUN_ID:-$(run_id)}"

COMMAND="${1:-}"
if [ -z "$COMMAND" ]; then
  usage
  exit 2
fi

case "$COMMAND" in
  doctor)
    run_doctor
    ;;
  prepare)
    run_prepare
    ;;
  build)
    run_build
    ;;
  test)
    run_tests
    ;;
  validate)
    run_validate
    ;;
  preflight)
    run_preflight
    ;;
  dry-run-testflight)
    run_dry_run_testflight
    ;;
  release-testflight)
    run_release_testflight
    ;;
  dry-run-appstore)
    run_dry_run_appstore
    ;;
  release-appstore)
    run_release_appstore
    ;;
  testflight)
    run_testflight_workflow
    ;;
  appstore)
    run_appstore_workflow
    ;;
  status)
    run_status
    ;;
  logs)
    run_logs
    ;;
  clean)
    run_clean
    ;;
  -h|--help|help)
    usage
    ;;
  *)
    usage
    error "unknown command: $COMMAND"
    ;;
esac
