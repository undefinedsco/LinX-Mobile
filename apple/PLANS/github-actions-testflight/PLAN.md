# GitHub Actions PLAN: LinXApple Build/Test 与 TestFlight 发布拆分

> 目标：为 `apple/` 原生 SwiftUI iOS App 提供两条独立 GitHub Actions 工作流。
>
> - `Apple Build and Test`：在 `macos-26` runner 上执行 XcodeGen、build、test。
> - `Apple TestFlight`：在 `macos-26` runner 上复用 `apple/.asc` 归档、导出并上传 TestFlight。
>
> 当前版本不包含本地语音模型或额外二进制 artifact 准备步骤。

---

## 1. 需求分析（What）

### 1.1 任务

新增：

```text
.github/
`-- workflows/
    |-- apple-build-test.yml
    `-- apple-testflight.yml
```

两个 workflow 只服务 `apple/` 下的 `LinXApple` 原生 iOS App，不改 React Native 根工程。

### 1.2 输入

工程输入：

- Xcode project: `apple/LinXApple.xcodeproj`
- XcodeGen spec: `apple/project.yml`
- Scheme: `LinXApple`
- Bundle identifier: `co.undefineds.linx.apple`
- Team ID: `X9RSF4AXVN`
- Release script: `apple/scripts/release-ios.sh`
- asc workflow: `apple/.asc/workflow.json`
- Export options: `apple/.asc/export-options-app-store.plist`

GitHub Variables：

| Name | 用途 |
|---|---|
| `LINX_APPLE_ASC_APP_ID` | App Store Connect app 数字 ID |
| `LINX_APPLE_TESTFLIGHT_GROUP` | TestFlight 分发组名称 |

GitHub Secrets：

| Name | 用途 |
|---|---|
| `ASC_KEY_ID` | App Store Connect API Key ID |
| `ASC_ISSUER_ID` | App Store Connect Issuer ID |
| `ASC_PRIVATE_KEY_P8_BASE64` | App Store Connect `.p8` 私钥 base64 |

### 1.3 输出

Build/Test workflow：

- Debug build gate
- Debug test gate
- `.xcresult` artifact
- `.asc/runs/*.log` artifact

TestFlight workflow：

- App Store Connect / TestFlight build
- `.ipa` artifact
- `.xcarchive` artifact
- `.asc/runs/*.log` artifact

---

## 2. 技术方案（How）

### 2.1 Apple Build and Test

文件：

```text
.github/workflows/apple-build-test.yml
```

触发：

- `push` 修改 `apple/**` 或该 workflow。
- `pull_request` 修改 `apple/**` 或该 workflow。

执行：

1. `actions/checkout@v4`
2. 安装 `xcodegen`
3. 缓存 SwiftPM 与 DerivedData
4. `cd apple && FORCE_XCODEGEN=1 ./scripts/release-ios.sh prepare`
5. 解析可用 iPhone Simulator，优先使用 `iPhone 16`
6. `xcodebuild build`
7. `xcodebuild test`
8. 上传 test result bundle 与 release script logs

### 2.2 Apple TestFlight

文件：

```text
.github/workflows/apple-testflight.yml
```

触发：

- `workflow_run`：`Apple Build and Test` 在 `main` 成功后自动发布。
- `workflow_dispatch`：手动触发，可选输入 `version`。

执行：

1. checkout 通过 build/test 的 commit；手动触发时 checkout 当前 ref。
2. 安装 `xcodegen` 与 `asc`。
3. 从 `ASC_PRIVATE_KEY_P8_BASE64` 写入临时 `.p8` 文件。
4. 生成 repo-local `apple/.asc/config.json`，供 `asc` 使用。
5. 将同一 `.p8` 路径注入 `ASC_XCODEBUILD_AUTH_KEY_PATH`、`ASC_XCODEBUILD_AUTH_KEY_ID`、`ASC_XCODEBUILD_AUTH_KEY_ISSUER_ID`，供 `xcodebuild -allowProvisioningUpdates` 自动签名使用。
6. `cd apple && FORCE_XCODEGEN=1 ./scripts/release-ios.sh prepare`
7. `cd apple && ./scripts/release-ios.sh testflight`
8. 上传 IPA、archive、logs artifacts。

### 2.3 asc workflow 调整

`apple/.asc/workflow.json` 继续作为 archive/export/upload 的 source of truth。

`testflight_beta` 与 `appstore_release` 的 archive/export 步骤支持可选环境变量：

```sh
ASC_XCODEBUILD_AUTH_KEY_PATH
ASC_XCODEBUILD_AUTH_KEY_ID
ASC_XCODEBUILD_AUTH_KEY_ISSUER_ID
```

当这些变量存在时，`.asc` workflow 会把它们转为 `asc xcode archive/export` 的 raw `xcodebuild` flags：

```text
-authenticationKeyPath
-authenticationKeyID
-authenticationKeyIssuerID
```

本地开发者未设置这些变量时，现有本地 keychain/profile 发布路径保持不变。

---

## 3. 文件结构（Folder & Files）

```text
.
|-- .github/
|   `-- workflows/
|       |-- apple-build-test.yml
|       `-- apple-testflight.yml
`-- apple/
    |-- .asc/
    |   |-- export-options-app-store.plist
    |   `-- workflow.json
    |-- scripts/
    |   `-- release-ios.sh
    |-- project.yml
    `-- LinXApple.xcodeproj
```

---

## 4. 使用方式（Usage）

### 4.1 配置 GitHub Variables

```text
LINX_APPLE_ASC_APP_ID=<App Store Connect app id>
LINX_APPLE_TESTFLIGHT_GROUP=<TestFlight group name>
```

### 4.2 配置 GitHub Secrets

```text
ASC_KEY_ID=<App Store Connect API key id>
ASC_ISSUER_ID=<App Store Connect issuer id>
ASC_PRIVATE_KEY_P8_BASE64=<base64 encoded AuthKey_XXXXXX.p8>
```

生成私钥 base64：

```sh
base64 -i AuthKey_XXXXXX.p8 | pbcopy
```

### 4.3 自动流程

- PR 或 push 修改 `apple/**`：运行 `Apple Build and Test`。
- `main` 分支 `Apple Build and Test` 成功：运行 `Apple TestFlight`。
- 手动发布：在 GitHub Actions 页面运行 `Apple TestFlight`，可选输入 `version`；留空时读取 `apple/project.yml` 的 `MARKETING_VERSION`。

---

## 5. 验收标准

- `.github/workflows/apple-build-test.yml` 存在且可解析。
- `.github/workflows/apple-testflight.yml` 存在且可解析。
- `apple/.asc/workflow.json` 是合法 JSON，且 `asc workflow validate --file .asc/workflow.json` 通过。
- `xcodegen generate --spec apple/project.yml` 通过。
- `xcodebuild -list -project apple/LinXApple.xcodeproj` 通过。
- `xcodebuild test -project apple/LinXApple.xcodeproj -scheme LinXApple -destination 'platform=iOS Simulator,name=iPhone 16'` 通过。

---

## 6. 注意事项

- 两个 workflow 都固定使用 `macos-26`，即 GitHub-hosted macOS 26 Apple Silicon runner。
- TestFlight workflow 不在 PR 上运行，避免发布 secrets 暴露给 PR 环境。
- `ASC_PRIVATE_KEY_P8_BASE64` 只能放在 GitHub Secrets；生成的 `.asc/config.json`、`.asc/tmp/`、IPA、archive、xcresult 已由 `apple/.asc/.gitignore` 忽略。
- `workflow_run` checkout 使用 `github.event.workflow_run.head_sha`，确保发布的是已经通过 build/test 的同一份代码。
