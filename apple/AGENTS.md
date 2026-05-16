# AGENTS.md

This file applies to all work under `apple/`.

## Role

Act as a senior iOS engineer working on the standalone native LinX Apple app.
Favor small, production-ready changes that preserve Swift 6 strict concurrency,
the existing SwiftUI architecture, and the current feature boundaries.

## Project

`apple/` contains a native SwiftUI iOS application independent from the React
Native app at the repository root.

Core project files:

```text
apple/
|-- project.yml
|-- LinXApple.xcodeproj
|-- LinXApple/
|   |-- Resources/
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

- iOS deployment target: `17.0`
- Swift version: `6.0`
- Strict concurrency: `complete`
- Project generator: XcodeGen
- Package manager: Swift Package Manager

Regenerate the project only after editing `project.yml`:

```sh
xcodegen generate
```

## Dependencies

Declared in `project.yml`:

- `AppAuth`: OIDC authorization code + PKCE
- `ExyteChat`: chat UI
- `SwiftOpenAI`: OpenAI-compatible runtime client
- `MarkdownView`: assistant markdown rendering

Do not add new dependencies unless the feature cannot be implemented cleanly
with SwiftUI, Foundation, Security, URLSession, or existing packages.

## Architecture Boundaries

### AppCore

Use for app entry, root routing, shared domain models, constants, date helpers,
and small UIKit bridge helpers.

Do not put networking, storage, or screen-specific business logic here.

### Auth

Use for authentication and session persistence:

- OIDC discovery
- dynamic client registration
- AppAuth authorization flow
- Keychain storage
- access token refresh
- WebID extraction

Keep all token handling in this module. Do not pass raw refresh tokens into UI
types.

### ChatUI

Use for SwiftUI screens, chat interaction state, user actions, and view-model
orchestration.

`ChatExperienceModel` is the coordinator for chat behavior. Keep direct SPARQL,
Keychain, and runtime implementation details out of SwiftUI views.

### PodData

Use for Pod storage, RDF/Turtle resources, SPARQL query construction, and
authorized Pod HTTP calls.

Keep string construction centralized in `PodSPARQLBuilder`. Use
`escapeLiteral(_:)` for all user-generated string values inserted into SPARQL or
Turtle content.

### Runtime

Use for LinX runtime and OpenAI-compatible API calls:

- model catalog lookup
- preferred model selection
- streamed chat completions
- non-streaming fallback behavior

Do not call `SwiftOpenAI` directly from UI views.

## Concurrency Rules

- Preserve `@MainActor` on observable UI coordinators and repositories that are
  currently main-actor isolated.
- Use `async/await` for network operations.
- Use `Task` from SwiftUI event handlers only to bridge user actions into async
  model methods.
- Handle cancellation explicitly for streaming chat flows.
- Keep mutable UI state updates on the main actor.
- Do not introduce detached tasks for UI or authentication work.

## Storage Rules

- Store authenticated session state only through `KeychainSessionStore`.
- Store chat history through `PodChatRepository`.
- Preserve the current Pod resource layout:

```text
{podBase}/.data/chat/ios-default/index.ttl
{podBase}/.data/chat/ios-default/yyyy/mm/dd/messages.ttl
{podBase}/.data/agents/linx-ios-assistant.ttl
```

- The native Apple app does not merge or migrate CLI history from
  `cli-default`.
- Keep WebID-to-Pod URL behavior in `PodStoragePaths`.

## UI Rules

- Build native UI with SwiftUI.
- Keep Exyte-specific message adaptation in `ExyteMessageAdapter`.
- Render assistant markdown through `AssistantMarkdownBubble`.
- Keep screen views lightweight; move workflow logic into `ChatExperienceModel`
  or a focused service type.
- Avoid adding UIKit unless it is required for platform integration, such as the
  current presenter lookup used by AppAuth.

## Error Handling

- Surface user-facing errors through existing published error state.
- Use `LinxAppError` for domain-specific failures.
- Preserve token-refresh retry behavior in `PodSPARQLClient`.
- Preserve streaming fallback behavior in `LinxOpenAIChatService`.

## Testing

Add or update tests when changing:

- JWT parsing
- WebID or Pod URL derivation
- SPARQL literal escaping or query generation
- model selection
- authentication request construction
- repository behavior that can be isolated without live network access

Existing test locations:

```text
LinXAppleTests/
LinXAppleUITests/
```

Preferred test command:

```sh
xcodebuild test \
  -project apple/LinXApple.xcodeproj \
  -scheme LinXApple \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

## Change Discipline

- Keep file ownership aligned with the module boundaries above.
- Avoid broad refactors while implementing a targeted feature or bug fix.
- Do not edit generated Xcode project files manually when the change belongs in
  `project.yml`.
- Do not modify the React Native app from this directory unless the task
  explicitly requires cross-surface integration.
- Do not commit secrets, access tokens, refresh tokens, WebIDs, or local machine
  paths.
