# LinXApple asc Release Workflow

This implementation keeps the release entry point in `scripts/release-ios.sh`
and stores repo-local asc workflow files under `.asc/`.

## Commands

```sh
./scripts/release-ios.sh doctor
VERSION=0.1.1 ASC_APP_ID=<APP_ID> ./scripts/release-ios.sh validate
DRY_RUN=1 VERSION=0.1.1 ASC_APP_ID=<APP_ID> TESTFLIGHT_GROUP="External Testers" ./scripts/release-ios.sh testflight
CONFIRM=1 VERSION=0.1.1 ASC_APP_ID=<APP_ID> TESTFLIGHT_GROUP="External Testers" ./scripts/release-ios.sh testflight
CONFIRM=1 VERSION=0.1.1 ASC_APP_ID=<APP_ID> ./scripts/release-ios.sh appstore
ASC_APP_ID=<APP_ID> ./scripts/release-ios.sh status
```

## Authentication

Local machines can use an asc keychain profile:

```sh
asc auth login \
  --name "LinXApple" \
  --key-id "<KEY_ID>" \
  --issuer-id "<ISSUER_ID>" \
  --private-key /path/to/AuthKey_<KEY_ID>.p8
```

Run with `ASC_PROFILE=LinXApple` when a non-default profile is required. CI can
use `ASC_BYPASS_KEYCHAIN=1` and environment or `.asc/config.json` credentials.
Do not commit `.p8` keys or `.asc/config.json`.

## Safety

`testflight` and `appstore` mutate App Store Connect state and require
`CONFIRM=1`. `DRY_RUN=1` runs `asc workflow run --dry-run` and does not upload
or submit.
