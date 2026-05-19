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
  doctor      Check asc, xcodebuild, plutil, and asc authentication
  validate    Validate workflow syntax and App Store Connect release readiness
  testflight  Archive, export, upload, and distribute to TestFlight
  appstore    Archive, export, upload, and submit for App Store review
  status      Show App Store Connect release status

Required environment:
  ASC_APP_ID or APP_ID   App Store Connect app ID
  VERSION               Marketing version for validate/testflight/appstore

Safety:
  CONFIRM=1 is required for testflight/appstore unless DRY_RUN=1.
USAGE
}

require_tool() {
  command -v "$1" >/dev/null 2>&1 || error "$1 is not installed or not on PATH"
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

run_workflow() {
  workflow_name="$1"
  shift

  if [ "${DRY_RUN:-0}" = "1" ]; then
    asc_run workflow run --file .asc/workflow.json --dry-run "$workflow_name" "$@"
  else
    asc_run workflow run --file .asc/workflow.json "$workflow_name" "$@"
  fi
}

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
APPLE_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
cd "$APPLE_DIR"

COMMAND="${1:-}"
if [ -z "$COMMAND" ]; then
  usage
  exit 2
fi

require_tool asc
require_tool xcodebuild
require_tool plutil

case "$COMMAND" in
  doctor)
    asc_run auth status --validate
    asc_run auth doctor
    ;;
  validate)
    require_app_id
    require_version
    asc_run workflow validate --file .asc/workflow.json
    asc_run validate --app "$APP_ID_VALUE" --version "$VERSION" --platform IOS --output table
    ;;
  testflight)
    require_app_id
    require_version
    [ -n "${TESTFLIGHT_GROUP:-}" ] || error "TESTFLIGHT_GROUP is required"
    require_confirmed_mutation
    run_workflow \
      testflight_beta \
      "APP_ID:$APP_ID_VALUE" \
      "VERSION:$VERSION" \
      "TESTFLIGHT_GROUP:$TESTFLIGHT_GROUP" \
      "SUBMIT_BETA_REVIEW:${SUBMIT_BETA_REVIEW:-0}" \
      "CONFIRM:${CONFIRM:-0}"
    ;;
  appstore)
    require_app_id
    require_version
    require_confirmed_mutation
    run_workflow \
      appstore_release \
      "APP_ID:$APP_ID_VALUE" \
      "VERSION:$VERSION" \
      "CONFIRM:${CONFIRM:-0}"
    ;;
  status)
    require_app_id
    asc_run status --app "$APP_ID_VALUE" --output table
    ;;
  -h|--help|help)
    usage
    ;;
  *)
    usage
    error "unknown command: $COMMAND"
    ;;
esac
