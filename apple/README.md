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
- `ExyteChat` `3.0.2`
- `SwiftOpenAI` `4.4.9`
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
cd apple
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

## Development Notes

- Keep UI views lightweight and move workflow logic into `ChatExperienceModel`
  or focused service types.
- Keep auth and token handling in `Auth`.
- Keep SPARQL and Pod storage details in `PodData`.
- Keep runtime API calls in `Runtime`.
- Preserve Swift 6 strict concurrency compatibility.
- Do not store credentials, access tokens, refresh tokens, or private WebIDs in
  the repository.
