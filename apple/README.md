# LinXApple

`LinXApple` is the standalone native SwiftUI iOS app in this repository. It is
separate from the React Native `LinXMobile` app at the repository root.

The app provides native OIDC login, Pod-backed chat history, and a LinX runtime
chat experience.

## Project Layout

```text
apple/
|-- project.yml
|-- LinXApple.xcodeproj
|-- LinXApple/
|   |-- Resources/
|   |   `-- Info.plist
|   `-- Sources/
|       |-- AppCore/
|       |-- Auth/
|       |-- ChatUI/
|       |-- PodData/
|       `-- Runtime/
|-- LinXAppleTests/
`-- LinXAppleUITests/
```

## Build Settings

- App target: `LinXApple`
- Bundle identifier: `co.undefineds.linx.apple`
- iOS deployment target: `17.0`
- Swift version: `6.0`
- Strict concurrency: `complete`
- Project generator: XcodeGen
- Package manager: Swift Package Manager

## Dependencies

Dependencies are declared in `project.yml`:

- `AppAuth` `2.0.0`
- `ExyteChat` `3.1.1`
- `MarkdownView` `2.6.1`

## Source Modules

### AppCore

App lifecycle, root routing, shared domain models, constants, date formatting,
and UIKit bridge helpers.

Important files:

- `LinXAppleApp.swift`
- `RootView.swift`
- `DomainModels.swift`
- `AppConstants.swift`
- `LinxDate.swift`
- `UIApplication+TopController.swift`

### Auth

OIDC login, dynamic client registration, AppAuth PKCE flow, token refresh, WebID
extraction, and Keychain persistence.

Important files:

- `AuthSessionController.swift`
- `OIDCDiscoveryClient.swift`
- `DynamicClientRegistrar.swift`
- `PKCECoordinator.swift`
- `JWTUtilities.swift`
- `KeychainSessionStore.swift`

### ChatUI

SwiftUI screens and chat state orchestration.

Important files:

- `ChatExperienceModel.swift`
- `ChatScene.swift`
- `LoginView.swift`
- `ThreadListView.swift`
- `AssistantMarkdownBubble.swift`
- `ExyteMessageAdapter.swift`

### PodData

Pod storage, RDF/Turtle resources, SPARQL query and update generation, and
authorized Pod HTTP requests.

Important files:

- `PodChatRepository.swift`
- `PodSPARQLClient.swift`
- `PodSPARQLBuilder.swift`
- `PodBootstrapper.swift`
- `PodStoragePaths.swift`
- `PodSPARQLTypes.swift`

### Runtime

LinX runtime API integration and OpenAI-compatible chat completions.

Important files:

- `LinxModelCatalogClient.swift`
- `LinxOpenAIChatService.swift`

## Runtime Flow

```text
LinXAppleApp
--> RootView
--> AuthSessionController.restore()
--> ChatExperienceModel.bootstrapIfNeeded()
--> PodBootstrapper.bootstrap()
--> ChatScene
--> ChatExperienceModel.enqueueSend()
--> PodChatRepository append user message
--> PodChatRepository append assistant placeholder
--> LinxOpenAIChatService stream reply
--> ChatExperienceModel patches assistant response into the Pod
```

## Authentication Flow

```text
OIDC discovery
--> dynamic client registration
--> AppAuth authorization code + PKCE
--> ID token WebID extraction
--> OIDAuthState stored in Keychain
--> authenticated app state
```

## Pod Storage Layout

```text
{podBase}/.data/
|-- chat/
|   `-- ios-default/
|       |-- index.ttl
|       `-- yyyy/mm/dd/messages.ttl
`-- agents/
    `-- linx-ios-assistant.ttl
```

The native Apple app keeps its chat history in `ios-default`. Existing CLI
history in `cli-default` is not merged or migrated into the app.

## Setup

Regenerate the Xcode project after editing `project.yml`:

```sh
xcodegen generate
```

Open the project:

```sh
open apple/LinXApple.xcodeproj
```

Select the `LinXApple` scheme and run on an iOS simulator or device.

## Tests

Run tests from Xcode with the `LinXApple` scheme, or from the repository root:

```sh
xcodebuild test \
  -project apple/LinXApple.xcodeproj \
  -scheme LinXApple \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

Existing tests cover:

- JWT WebID extraction
- WebID to Pod base URL resolution
- preferred model selection
- SPARQL literal escaping
- PKCE authorization request construction
- launch-to-login UI behavior

## Release Workflow

The App Store Connect release entry point is `scripts/release-ios.sh`. It wraps
repo-local asc workflow files under `.asc/` and keeps generated archives, IPAs,
reports, runs, and credentials out of source control.

GitHub Actions provide two macOS workflows for CI and TestFlight publishing:

- `Apple Build and Test`: runs XcodeGen, builds, and tests LinXApple when
  `apple/**` or the build/test workflow changes on push or pull request.
- `Apple TestFlight`: runs after `Apple Build and Test` succeeds on `main`, or
  when started manually from the GitHub Actions page.

### GitHub Actions Setup

Configure these repository variables:

| Variable | Description |
|---|---|
| `LINX_APPLE_ASC_APP_ID` | App Store Connect numeric app ID |
| `LINX_APPLE_TESTFLIGHT_GROUP` | TestFlight group name |

Configure these repository secrets:

| Secret | Description |
|---|---|
| `ASC_KEY_ID` | App Store Connect API key ID |
| `ASC_ISSUER_ID` | App Store Connect issuer ID |
| `ASC_PRIVATE_KEY_P8_BASE64` | Base64-encoded App Store Connect `.p8` private key |

Create the base64 private key value on macOS:

```sh
base64 -i AuthKey_<KEY_ID>.p8 | pbcopy
```

The TestFlight workflow writes the key to a temporary ignored path, creates a
repo-local `.asc/config.json`, and passes the same key to `xcodebuild` for
automatic signing with `-allowProvisioningUpdates`.

Manual TestFlight publish:

1. Open GitHub Actions.
2. Select `Apple TestFlight`.
3. Run the workflow.
4. Optionally enter `version`; leave it empty to use `MARKETING_VERSION` from
   `apple/project.yml`.

### Local Release Tools

Install asc:

```sh
brew install asc
```

Create an App Store Connect API key in App Store Connect, then register it with
asc on local machines:

```sh
asc auth login \
  --name "LinXApple" \
  --key-id "<KEY_ID>" \
  --issuer-id "<ISSUER_ID>" \
  --private-key /path/to/AuthKey_<KEY_ID>.p8
```

Use `ASC_PROFILE=LinXApple` when the keychain profile is not the default. In CI,
set `ASC_BYPASS_KEYCHAIN=1` and provide credentials through CI secrets or an
untracked `.asc/config.json`.

Prepare generated files:

```sh
./scripts/release-ios.sh prepare
```

Build the app locally:

```sh
./scripts/release-ios.sh build
```

Run the native test suite:

```sh
./scripts/release-ios.sh test
```

The build command defaults to `BUILD_DESTINATION='generic/platform=iOS'`. The
test command defaults to `DESTINATION='platform=iOS Simulator,name=iPhone 16'`.
Both can be overridden through environment variables.

Run App Store Connect validation only:

```sh
VERSION=0.1.1 ASC_APP_ID=<APP_STORE_CONNECT_APP_ID> ./scripts/release-ios.sh validate
```

Run the full preflight before release. This checks asc auth, prepares local
artifacts, runs tests, and validates App Store Connect readiness:

```sh
VERSION=0.1.1 \
ASC_APP_ID=<APP_STORE_CONNECT_APP_ID> \
./scripts/release-ios.sh preflight
```

Use `SKIP_TESTS=1` only when you explicitly need to bypass local tests.

Dry-run TestFlight and App Store workflows before uploading or submitting:

```sh
VERSION=0.1.1 \
ASC_APP_ID=<APP_STORE_CONNECT_APP_ID> \
TESTFLIGHT_GROUP="External Testers" \
./scripts/release-ios.sh dry-run-testflight

VERSION=0.1.1 \
ASC_APP_ID=<APP_STORE_CONNECT_APP_ID> \
./scripts/release-ios.sh dry-run-appstore
```

Run preflight, then upload and distribute TestFlight:

```sh
CONFIRM=1 \
VERSION=0.1.1 \
ASC_APP_ID=<APP_STORE_CONNECT_APP_ID> \
TESTFLIGHT_GROUP="External Testers" \
./scripts/release-ios.sh release-testflight
```

Run preflight, then submit App Store review:

```sh
CONFIRM=1 \
VERSION=0.1.1 \
ASC_APP_ID=<APP_STORE_CONNECT_APP_ID> \
./scripts/release-ios.sh release-appstore
```

The lower-level `testflight` and `appstore` commands are still available when
you intentionally want to skip the local preflight and run only the asc workflow.
They still require `CONFIRM=1` unless `DRY_RUN=1` is set.

Check release status:

```sh
ASC_APP_ID=<APP_STORE_CONNECT_APP_ID> ./scripts/release-ios.sh status
```

Inspect the latest local build or test log:

```sh
./scripts/release-ios.sh logs
```

Clean generated release artifacts, reports, and logs:

```sh
CONFIRM=1 ./scripts/release-ios.sh clean
```

## Development Notes

- Keep UI views lightweight and move workflow logic into `ChatExperienceModel`
  or focused service types.
- Keep auth and token handling in `Auth`.
- Keep SPARQL and Pod storage details in `PodData`.
- Keep runtime API calls in `Runtime`.
- Preserve Swift 6 strict concurrency compatibility.
- Do not store credentials, access tokens, refresh tokens, or private WebIDs in
  the repository.
