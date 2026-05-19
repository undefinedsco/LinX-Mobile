# PLAN-asc.md

# Release PLAN: asccli 接入 LinXApple IPA 上传与审核工作流

> 目标：为当前 `apple/` 原生 SwiftUI iOS App 增加一套可重复运行的发布工作流，通过 `asc`/asccli 完成 IPA 构建产物上传、TestFlight 外部测试审核、App Store 正式版本提交审核。
>
> 首版交付形态：新增 repo-local 配置与 shell 入口脚本，后续运行脚本即可完成 doctor、validate、TestFlight 发布、App Store 提交审核和状态查看。
>
> 首版不做：自动维护 App Store metadata、截图、隐私表单、价格、证书轮换、provisioning profile 创建、审核通过后的自动上架策略。

---

## 0. 当前工程事实

本计划只适用于当前 `LinXApple` 工程。

```text
apple/
|-- project.yml
|-- LinXApple.xcodeproj
|-- LinXApple/
|-- LinXAppleTests/
|-- LinXAppleUITests/
|-- README.md
`-- scripts/
```

工程配置：

- App target: `LinXApple`
- Scheme: `LinXApple`
- Bundle identifier: `co.undefineds.linx.apple`
- Development team: `X9RSF4AXVN`
- iOS deployment target: `17.0`
- Swift version: `6.0`
- Signing style: `Automatic`
- Project generator: XcodeGen，source of truth is `project.yml`
- 当前 target-level `CURRENT_PROJECT_VERSION`: `6`
- 当前 `MARKETING_VERSION`: `0.1.0`

现有脚本风格参考：

- `scripts/copy-giphy-dsym.sh` 使用 `set -eu`
- 脚本应显式校验工具是否存在
- 出错时输出清晰的 `error:` 消息并非零退出
- 不把凭证、token、私钥或本机绝对路径写入仓库

---

## 1. 总体目标

### 1.1 发布能力目标

- 支持本机和 CI 两种运行方式
- 支持安装检查和 asc 认证检查
- 支持校验 App Store Connect 发布准备状态
- 支持构建 Release archive
- 支持导出 App Store Connect IPA
- 支持自动获取 App Store Connect 下一个 build number
- 支持上传 IPA 到 App Store Connect
- 支持 TestFlight 外部测试组分发和 Beta App Review 提交
- 支持 App Store 正式版本提交审核
- 支持发布后查看审核与处理状态
- 所有上传或提交审核动作都需要显式确认

### 1.2 工程目标

- 发布入口固定为 `scripts/release-ios.sh`
- asc workflow 配置固定放在 `.asc/workflow.json`
- IPA、archive、报告等产物固定放在 `.asc/artifacts/` 和 `.asc/reports/`
- 私钥、repo-local asc config、构建产物都必须被忽略
- 不修改 `LinXApple.xcodeproj` 生成文件
- 不修改 `project.yml`，除非后续需要把 release script 接入 Xcode build phase
- 脚本通过命令行覆盖 `MARKETING_VERSION` 和 `CURRENT_PROJECT_VERSION`

---

## 2. 新增文件结构

推荐新增：

```text
apple/
|-- .asc/
|   |-- .gitignore
|   |-- export-options-app-store.plist
|   `-- workflow.json
|-- docs/
|   `-- PLAN-asc.md
`-- scripts/
    `-- release-ios.sh
```

说明：

- `.asc/workflow.json` 负责组合 asc 与 Xcode 构建命令。
- `.asc/export-options-app-store.plist` 负责 IPA export 配置。
- `.asc/.gitignore` 防止发布产物和凭证进入版本库。
- `scripts/release-ios.sh` 是人工和 CI 都调用的唯一入口。
- `docs/PLAN-asc.md` 记录实现计划、变量约定、运行方式和验证步骤。

---

## 3. asc 安装与认证

### 3.1 安装

macOS 推荐使用 Homebrew：

```sh
brew install asc
```

也可以使用官方安装脚本：

```sh
curl -fsSL https://asccli.sh/install | bash
```

安装后检查：

```sh
asc version
asc --help
```

### 3.2 本机认证

本机开发者机器推荐使用 keychain profile：

```sh
asc auth login \
  --name "LinXApple" \
  --key-id "<KEY_ID>" \
  --issuer-id "<ISSUER_ID>" \
  --private-key /path/to/AuthKey_<KEY_ID>.p8
```

脚本运行时通过 `ASC_PROFILE` 指定 profile：

```sh
ASC_PROFILE=LinXApple ./scripts/release-ios.sh doctor
```

如果不设置 `ASC_PROFILE`，脚本使用 asc 当前默认认证配置。

### 3.3 CI 或无 keychain 环境认证

CI 环境推荐启用 keychain bypass：

```sh
export ASC_BYPASS_KEYCHAIN=1
```

再通过 CI secret 或 asc repo-local config 提供 API key 信息。脚本不应该读取或打印 `.p8` 文件内容，也不应该把 `.p8` 文件提交到仓库。

认证检查命令：

```sh
asc auth status --validate
asc auth doctor
```

---

## 4. 环境变量约定

### 4.1 必填变量

| 变量 | 用途 |
|---|---|
| `ASC_APP_ID` 或 `APP_ID` | App Store Connect app 数字 ID，例如 `1234567890` |
| `VERSION` | 本次发布的 marketing version，例如 `0.1.1` |

### 4.2 常用可选变量

| 变量 | 默认值 | 用途 |
|---|---:|---|
| `ASC_PROFILE` | 空 | asc 本机认证 profile 名称 |
| `TESTFLIGHT_GROUP` | 空 | TestFlight 分发组名称或 ID |
| `SUBMIT_BETA_REVIEW` | `0` | 是否提交 TestFlight 外部测试审核 |
| `DRY_RUN` | `0` | 是否只预演 workflow |
| `CONFIRM` | `0` | 是否允许上传、分发或提交审核 |
| `ASC_BYPASS_KEYCHAIN` | asc 默认 | CI/无交互认证模式 |
| `CONFIGURATION` | `Release` | Xcode 构建配置 |
| `SCHEME` | `LinXApple` | Xcode scheme |
| `PROJECT_PATH` | `LinXApple.xcodeproj` | Xcode project 路径 |

### 4.3 确认规则

`doctor`、`validate` 和 `status` 不需要 `CONFIRM=1`。

任何会上传 IPA、分发 TestFlight、提交 Beta App Review 或提交 App Store 正式审核的命令都必须显式设置：

```sh
CONFIRM=1
```

当 `DRY_RUN=1` 时，脚本只执行 workflow dry-run，不上传、不提交。

---

## 5. `.asc/export-options-app-store.plist`

新增文件 `.asc/export-options-app-store.plist`：

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key>
  <string>app-store-connect</string>
  <key>signingStyle</key>
  <string>automatic</string>
  <key>teamID</key>
  <string>X9RSF4AXVN</string>
  <key>uploadSymbols</key>
  <true/>
</dict>
</plist>
```

说明：

- `method=app-store-connect` 用于导出可上传 App Store Connect 的 IPA。
- `signingStyle=automatic` 复用当前 `project.yml` 的签名策略。
- CI 机器仍需要具备有效 Apple Distribution certificate 和 provisioning profile，或允许 Xcode 自动管理签名。

---

## 6. `.asc/.gitignore`

新增文件 `.asc/.gitignore`：

```gitignore
artifacts/
reports/
tmp/
config.json
*.p8
*.ipa
*.xcarchive
*.xcresult
*.json.tmp
```

保留可提交文件：

- `.asc/workflow.json`
- `.asc/export-options-app-store.plist`
- `.asc/.gitignore`

---

## 7. `scripts/release-ios.sh` 设计

### 7.1 命令形式

```sh
./scripts/release-ios.sh <command>
```

支持命令：

| 命令 | 行为 |
|---|---|
| `doctor` | 检查 asc、xcodebuild、plutil 和 asc auth 状态 |
| `validate` | 校验 workflow 与 App Store Connect 版本准备状态，不上传 |
| `testflight` | archive、export、上传 IPA、分发 TestFlight，可选提交 Beta App Review |
| `appstore` | archive、export、上传 IPA、提交 App Store 正式审核 |
| `status` | 查看当前 app release pipeline 状态 |

### 7.2 脚本行为

脚本应执行以下通用步骤：

1. `set -eu`
2. 切换到 `apple/` 工程根目录
3. 校验 `asc`、`xcodebuild`、`plutil` 是否存在
4. 解析 `APP_ID`：优先 `ASC_APP_ID`，其次 `APP_ID`
5. 按命令校验 `VERSION`、`TESTFLIGHT_GROUP`、`CONFIRM`
6. 如设置 `ASC_PROFILE`，为 asc 命令追加 `--profile "$ASC_PROFILE"`
7. `doctor` 调用 `asc auth status --validate` 和 `asc auth doctor`
8. `validate` 调用 `asc workflow validate --file .asc/workflow.json` 和 `asc validate`
9. `testflight` 调用 `asc workflow run --file .asc/workflow.json testflight_beta`
10. `appstore` 调用 `asc workflow run --file .asc/workflow.json appstore_release`
11. `status` 调用 `asc status --app "$APP_ID" --output table`

### 7.3 运行示例

安装和认证检查：

```sh
./scripts/release-ios.sh doctor
```

校验正式版本准备状态：

```sh
VERSION=0.1.1 \
ASC_APP_ID=<APP_STORE_CONNECT_APP_ID> \
./scripts/release-ios.sh validate
```

预演 TestFlight 流程：

```sh
DRY_RUN=1 \
VERSION=0.1.1 \
ASC_APP_ID=<APP_STORE_CONNECT_APP_ID> \
TESTFLIGHT_GROUP="External Testers" \
./scripts/release-ios.sh testflight
```

上传并分发 TestFlight：

```sh
CONFIRM=1 \
VERSION=0.1.1 \
ASC_APP_ID=<APP_STORE_CONNECT_APP_ID> \
TESTFLIGHT_GROUP="External Testers" \
./scripts/release-ios.sh testflight
```

上传、分发并提交 TestFlight 外部测试审核：

```sh
CONFIRM=1 \
SUBMIT_BETA_REVIEW=1 \
VERSION=0.1.1 \
ASC_APP_ID=<APP_STORE_CONNECT_APP_ID> \
TESTFLIGHT_GROUP="External Testers" \
./scripts/release-ios.sh testflight
```

预演 App Store 正式审核流程：

```sh
DRY_RUN=1 \
VERSION=0.1.1 \
ASC_APP_ID=<APP_STORE_CONNECT_APP_ID> \
./scripts/release-ios.sh appstore
```

上传并提交 App Store 正式审核：

```sh
CONFIRM=1 \
VERSION=0.1.1 \
ASC_APP_ID=<APP_STORE_CONNECT_APP_ID> \
./scripts/release-ios.sh appstore
```

查看状态：

```sh
ASC_APP_ID=<APP_STORE_CONNECT_APP_ID> \
./scripts/release-ios.sh status
```

---

## 8. `.asc/workflow.json` 设计

### 8.1 共享配置

workflow 顶层 env：

```json
{
  "env": {
    "APP_ID": "",
    "PROJECT_PATH": "LinXApple.xcodeproj",
    "SCHEME": "LinXApple",
    "CONFIGURATION": "Release",
    "EXPORT_OPTIONS": ".asc/export-options-app-store.plist",
    "ARTIFACTS_DIR": ".asc/artifacts",
    "VERSION": "",
    "TESTFLIGHT_GROUP": "",
    "SUBMIT_BETA_REVIEW": "0"
  }
}
```

### 8.2 通用构建链路

每个发布 workflow 复用同一条构建链路：

1. 校验 `APP_ID` 不为空
2. 校验 `VERSION` 不为空
3. 创建 `.asc/artifacts/`
4. 调用 `asc builds latest --next` 解析下一个 build number
5. 调用 `asc xcode archive` 生成 `.xcarchive`
6. 调用 `asc xcode export` 生成 `.ipa`
7. 后续 publish 命令消费导出的 IPA 路径

build number 解析命令：

```sh
asc builds latest \
  --app "$APP_ID" \
  --version "$VERSION" \
  --platform IOS \
  --next \
  --initial-build-number 1 \
  --output json
```

archive 命令应传入：

```sh
asc xcode archive \
  --project "$PROJECT_PATH" \
  --scheme "$SCHEME" \
  --configuration "$CONFIGURATION" \
  --archive-path ".asc/artifacts/LinXApple-$VERSION-$BUILD_NUMBER.xcarchive" \
  --clean \
  --overwrite \
  --xcodebuild-flag=-destination \
  --xcodebuild-flag=generic/platform=iOS \
  --xcodebuild-flag=-allowProvisioningUpdates \
  --xcodebuild-flag=MARKETING_VERSION=$VERSION \
  --xcodebuild-flag=CURRENT_PROJECT_VERSION=$BUILD_NUMBER \
  --output json
```

export 命令应传入：

```sh
asc xcode export \
  --archive-path "$ARCHIVE_PATH" \
  --export-options "$EXPORT_OPTIONS" \
  --ipa-path ".asc/artifacts/LinXApple-$VERSION-$BUILD_NUMBER.ipa" \
  --overwrite \
  --xcodebuild-flag=-allowProvisioningUpdates \
  --output json
```

### 8.3 TestFlight workflow

workflow 名称：`testflight_beta`

发布命令：

```sh
asc publish testflight \
  --app "$APP_ID" \
  --ipa "$IPA_PATH" \
  --group "$TESTFLIGHT_GROUP" \
  --wait \
  --poll-interval 10s \
  --output json
```

当 `SUBMIT_BETA_REVIEW=1` 且脚本层已确认 `CONFIRM=1` 时追加：

```sh
--submit --confirm
```

### 8.4 App Store workflow

workflow 名称：`appstore_release`

先运行 readiness validation：

```sh
asc validate \
  --app "$APP_ID" \
  --version "$VERSION" \
  --output json
```

通过后提交正式审核：

```sh
asc publish appstore \
  --app "$APP_ID" \
  --ipa "$IPA_PATH" \
  --version "$VERSION" \
  --submit \
  --confirm \
  --output json
```

---

## 9. README 更新

在 `README.md` 增加 `Release Workflow` 小节，内容包括：

- asc 安装方式
- App Store Connect API key 创建入口
- 本机认证命令
- CI 认证注意事项
- `scripts/release-ios.sh` 命令说明
- TestFlight 发布示例
- App Store 提交审核示例
- 发布前建议先运行测试

发布前测试命令：

```sh
xcodebuild test \
  -project LinXApple.xcodeproj \
  -scheme LinXApple \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

---

## 10. 验证步骤

### 10.1 静态验证

```sh
sh -n scripts/release-ios.sh
plutil -lint .asc/export-options-app-store.plist
asc workflow validate --file .asc/workflow.json
```

### 10.2 工具与认证验证

```sh
./scripts/release-ios.sh doctor
```

预期：

- 找到 `asc`
- 找到 `xcodebuild`
- 找到 `plutil`
- `asc auth status --validate` 通过
- `asc auth doctor` 没有阻塞性错误

### 10.3 发布准备验证

```sh
VERSION=0.1.1 \
ASC_APP_ID=<APP_STORE_CONNECT_APP_ID> \
./scripts/release-ios.sh validate
```

预期：

- workflow JSON 格式有效
- asc 能访问目标 app
- App Store Connect 版本准备状态可被读取
- 若 metadata、截图、隐私或合规信息缺失，`asc validate` 能提前暴露阻塞项

### 10.4 Dry run 验证

```sh
DRY_RUN=1 \
VERSION=0.1.1 \
ASC_APP_ID=<APP_STORE_CONNECT_APP_ID> \
TESTFLIGHT_GROUP="External Testers" \
./scripts/release-ios.sh testflight
```

```sh
DRY_RUN=1 \
VERSION=0.1.1 \
ASC_APP_ID=<APP_STORE_CONNECT_APP_ID> \
./scripts/release-ios.sh appstore
```

预期：

- 命令图正确
- 环境变量被正确传入 workflow
- artifact 路径稳定
- 不上传 IPA
- 不提交审核

### 10.5 TestFlight 实跑验证

```sh
CONFIRM=1 \
VERSION=0.1.1 \
ASC_APP_ID=<APP_STORE_CONNECT_APP_ID> \
TESTFLIGHT_GROUP="External Testers" \
./scripts/release-ios.sh testflight
```

预期：

- archive 成功
- export IPA 成功
- IPA 上传成功
- build processing 等待完成
- build 被加入目标 TestFlight group

如需提交外部测试审核：

```sh
CONFIRM=1 \
SUBMIT_BETA_REVIEW=1 \
VERSION=0.1.1 \
ASC_APP_ID=<APP_STORE_CONNECT_APP_ID> \
TESTFLIGHT_GROUP="External Testers" \
./scripts/release-ios.sh testflight
```

### 10.6 App Store 提交审核验证

```sh
CONFIRM=1 \
VERSION=0.1.1 \
ASC_APP_ID=<APP_STORE_CONNECT_APP_ID> \
./scripts/release-ios.sh appstore
```

预期：

- archive 成功
- export IPA 成功
- IPA 上传成功
- build 被关联到目标 App Store version
- 版本提交 App Review

提交后查看状态：

```sh
ASC_APP_ID=<APP_STORE_CONNECT_APP_ID> \
./scripts/release-ios.sh status
```

或：

```sh
asc status --app <APP_STORE_CONNECT_APP_ID> --watch
```

---

## 11. 风险与边界

### 11.1 App Store metadata 不完整

App Store 正式审核要求截图、描述、关键词、隐私、年龄分级、加密合规等信息已在 App Store Connect 就绪。首版脚本只通过 `asc validate` 暴露阻塞项，不自动补齐 metadata。

### 11.2 签名配置依赖运行机器

当前工程使用 automatic signing。CI 或新机器上仍需要有效 Apple Distribution certificate、provisioning profile、Apple Developer team 权限，或允许 Xcode 自动管理签名。首版不自动创建或轮换证书。

### 11.3 App Store 审核提交不等于自动发布

`asc publish appstore --submit --confirm` 表示提交 App Review。审核通过后的发布时间取决于 App Store Connect 版本设置。后续如需要自动发布、手动发布或定时发布策略，应单独加入 release policy 参数。

### 11.4 build number 来源

首版不使用 `project.yml` 中当前 `CURRENT_PROJECT_VERSION=6` 作为唯一来源，而是通过 App Store Connect 查询目标 version 的下一个 build number。这样可以避免重复上传已存在 build number。

### 11.5 审核动作必须显式确认

为避免误上传或误提交审核，任何会改变 App Store Connect 状态的命令都必须设置 `CONFIRM=1`。建议 CI job 也保留同样保护栏。

---

## 12. 实施顺序

1. 新增 `.asc/.gitignore`
2. 新增 `.asc/export-options-app-store.plist`
3. 新增 `.asc/workflow.json`
4. 新增 `scripts/release-ios.sh`
5. 更新 `README.md` 的 Release Workflow 章节
6. 运行 `sh -n scripts/release-ios.sh`
7. 运行 `plutil -lint .asc/export-options-app-store.plist`
8. 运行 `asc workflow validate --file .asc/workflow.json`
9. 使用 `DRY_RUN=1` 分别验证 `testflight` 和 `appstore`
10. 在确认 App Store Connect app ID、metadata、签名和认证均可用后，设置 `CONFIRM=1` 实跑

---

## 13. 后续增强

- 增加 `build-only` 命令，只 archive/export，不上传
- 增加 `metadata validate` 或 metadata sync 工作流
- 增加 screenshots 检查或上传工作流
- 增加 `asc signing` 证书和 profile 检查
- 增加 CI 示例，例如 GitHub Actions、GitLab CI、Bitrise 或 CircleCI
- 增加 release policy 参数，控制审核通过后手动发布、自动发布或定时发布