# GitHub Actions PLAN: LinXApple Build/Test 与 TestFlight 发布拆分

> 目标：为 `apple/` 原生 SwiftUI iOS App 增加两条独立 GitHub Actions 工作流。
>
> - `Apple Build and Test`：在 macOS runner 上完成 iOS build + test。
> - `Apple TestFlight`：在 macOS runner 上复用 `apple/.asc` 构建、导出并上传 TestFlight。
>
> 首版不做：React Native 根工程 CI、Android CI、App Store 正式提交、metadata/截图/隐私表单自动维护、证书/profile 自动创建。

---

## 1. 需求分析（What）

### 1.1 明确任务

为当前仓库新增两个独立 workflow：

```text
.github/
`-- workflows/
    |-- apple-build-test.yml
    `-- apple-testflight.yml
```

两个 workflow 都只服务 `apple/` 下的 `LinXApple` 原生 iOS App。

### 1.2 输入

工程输入：

- Xcode project: `apple/LinXApple.xcodeproj`
- XcodeGen spec: `apple/project.yml`
- Scheme: `LinXApple`
- Bundle identifier: `co.undefineds.linx.apple`
- Team ID: `X9RSF4AXVN`
- Release entry point: `apple/scripts/release-ios.sh`
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

Build/Test workflow 输出：

- Xcode build 结果
- Xcode test 结果
- `.xcresult` artifact
- `.asc/runs/*.log` artifact

TestFlight workflow 输出：

- `.ipa` artifact
- `.xcarchive` artifact
- `.asc/runs/*.log` artifact
- App Store Connect / TestFlight 中的新 build

### 1.4 边界条件

- CI 必须先准备未入库的 Whisper artifacts：

  ```sh
  cd apple
  scripts/prepare-whisper.sh
  ```

- CI 必须通过 XcodeGen 保证 `LinXApple.xcodeproj` 与 `project.yml` 同步：

  ```sh
  cd apple
  xcodegen generate --spec project.yml
  ```

- TestFlight 发布不在 PR 上运行。
- TestFlight 自动发布只在 `main` 分支 build/test 成功后运行。
- 手动触发 TestFlight workflow 时允许输入 `VERSION`。
- 自动触发 TestFlight workflow 时从 `project.yml` 读取 `MARKETING_VERSION`。

---

## 2. 技术方案（How）

### 2.1 Workflow 一：Apple Build and Test

文件：

```text
.github/workflows/apple-build-test.yml
```

触发策略：

```yaml
name: Apple Build and Test

on:
  push:
    paths:
      - "apple/**"
      - ".github/workflows/apple-build-test.yml"
  pull_request:
    paths:
      - "apple/**"
      - ".github/workflows/apple-build-test.yml"
```

Runner：

```yaml
runs-on: macos-latest
```

核心步骤：

1. `actions/checkout`
2. 安装 `xcodegen`
3. 缓存：
   - `apple/.build/whisper`
   - `~/Library/Developer/Xcode/DerivedData`
   - `~/Library/Caches/org.swift.swiftpm`
4. `cd apple && ./scripts/release-ios.sh prepare`
5. 解析可用 iPhone simulator，优先使用 `iPhone 16`，不存在时选择第一台可用 iPhone。
6. 执行 Debug build。
7. 执行 Debug test，并写入 `.asc/reports/tests-${RUN_ID}.xcresult`。
8. 上传 `.xcresult` 和 `.asc/runs/*.log` artifacts。

构建命令：

```sh
cd apple
xcodebuild \
  build \
  -project LinXApple.xcodeproj \
  -scheme LinXApple \
  -configuration Debug \
  -destination "$TEST_DESTINATION"
```

测试命令：

```sh
cd apple
xcodebuild \
  test \
  -project LinXApple.xcodeproj \
  -scheme LinXApple \
  -configuration Debug \
  -destination "$TEST_DESTINATION" \
  -resultBundlePath ".asc/reports/tests-${GITHUB_RUN_ID}.xcresult"
```

### 2.2 Workflow 二：Apple TestFlight

文件：

```text
.github/workflows/apple-testflight.yml
```

触发策略：

```yaml
name: Apple TestFlight

on:
  workflow_run:
    workflows:
      - Apple Build and Test
    branches:
      - main
    types:
      - completed
  workflow_dispatch:
    inputs:
      version:
        description: "Marketing version. Empty value reads MARKETING_VERSION from apple/project.yml."
        required: false
        type: string
```

运行条件：

```yaml
if: >
  github.event_name == 'workflow_dispatch' ||
  github.event.workflow_run.conclusion == 'success'
```

Runner：

```yaml
runs-on: macos-latest
```

核心步骤：

1. `actions/checkout`
   - `workflow_run` 使用 `github.event.workflow_run.head_sha`
   - `workflow_dispatch` 使用当前 ref
2. 安装 `xcodegen`
3. 安装 `asc`
4. 写入临时 App Store Connect 私钥：

   ```sh
   mkdir -p apple/.asc/tmp
   printf '%s' "$ASC_PRIVATE_KEY_P8_BASE64" | base64 --decode > apple/.asc/tmp/AuthKey.p8
   chmod 600 apple/.asc/tmp/AuthKey.p8
   ```

5. 写入 repo-local `apple/.asc/config.json`：

   ```json
   {
     "key_id": "${ASC_KEY_ID}",
     "issuer_id": "${ASC_ISSUER_ID}",
     "private_key_path": ".asc/tmp/AuthKey.p8",
     "app_id": "${ASC_APP_ID}"
   }
   ```

6. 执行：

   ```sh
   cd apple
   ./scripts/release-ios.sh testflight
   ```

7. 上传 `.ipa`、`.xcarchive`、logs artifacts。

### 2.3 asc 认证与发布模型

TestFlight workflow 使用 repo-local `apple/.asc/config.json`，并设置：

```sh
ASC_BYPASS_KEYCHAIN=1
ASC_STRICT_AUTH=true
CONFIRM=1
```

发布入口固定复用现有脚本：

```sh
cd apple
./scripts/release-ios.sh testflight
```

该命令会进入 `apple/.asc/workflow.json` 的 `testflight_beta` workflow，执行：

1. 读取下一个 build number。
2. `asc xcode archive`
3. `asc xcode export`
4. `asc publish testflight`

---

## 3. 架构与模块边界

### 3.1 CI 分层

```text
GitHub Actions
|-- apple-build-test.yml
|   |-- prepare whisper artifacts
|   |-- xcodegen generate
|   |-- xcodebuild build
|   `-- xcodebuild test
|
`-- apple-testflight.yml
    |-- prepare asc credentials
    |-- prepare whisper artifacts
    |-- xcodegen generate
    `-- scripts/release-ios.sh testflight
        `-- .asc/workflow.json
```

### 3.2 代码边界

- `.github/workflows/apple-build-test.yml` 只负责 CI 编译与测试。
- `.github/workflows/apple-testflight.yml` 只负责发布前置环境和触发 release script。
- `apple/scripts/release-ios.sh` 继续作为本地与 CI 的统一发布入口。
- `apple/.asc/workflow.json` 继续作为 asc archive/export/upload 的 source of truth。
- 不修改 Swift 源码。
- 不修改 React Native 根工程。
- 不手动编辑 Xcode project 的生成文件。

---

## 4. 文件结构（Folder & Files）

实现后结构：

```text
.
|-- .github/
|   `-- workflows/
|       |-- apple-build-test.yml
|       `-- apple-testflight.yml
`-- apple/
    |-- .asc/
    |   |-- .gitignore
    |   |-- export-options-app-store.plist
    |   `-- workflow.json
    |-- PLANS/
    |   `-- github-actions-testflight/
    |       `-- PLAN.md
    |-- scripts/
    |   |-- prepare-whisper.sh
    |   `-- release-ios.sh
    |-- project.yml
    `-- LinXApple.xcodeproj
```

---

## 5. 完整可运行配置（Code）

### 5.1 `.github/workflows/apple-build-test.yml`

```yaml
name: Apple Build and Test

on:
  push:
    paths:
      - "apple/**"
      - ".github/workflows/apple-build-test.yml"
  pull_request:
    paths:
      - "apple/**"
      - ".github/workflows/apple-build-test.yml"

concurrency:
  group: apple-build-test-${{ github.ref }}
  cancel-in-progress: true

jobs:
  build-test:
    name: Build and Test LinXApple
    runs-on: macos-latest
    timeout-minutes: 60

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Install XcodeGen
        run: |
          if ! command -v xcodegen >/dev/null 2>&1; then
            brew install xcodegen
          fi

      - name: Cache Whisper artifacts
        uses: actions/cache@v4
        with:
          path: apple/.build/whisper
          key: whisper-v1.8.4-${{ runner.os }}

      - name: Cache SwiftPM and DerivedData
        uses: actions/cache@v4
        with:
          path: |
            ~/Library/Caches/org.swift.swiftpm
            ~/Library/Developer/Xcode/DerivedData
          key: apple-spm-deriveddata-${{ runner.os }}-${{ hashFiles('apple/LinXApple.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved') }}
          restore-keys: |
            apple-spm-deriveddata-${{ runner.os }}-

      - name: Prepare LinXApple
        run: |
          cd apple
          ./scripts/release-ios.sh prepare

      - name: Resolve simulator destination
        id: destination
        run: |
          set -euo pipefail
          if xcrun simctl list devices available | grep -q "iPhone 16"; then
            echo "value=platform=iOS Simulator,name=iPhone 16,OS=latest" >> "$GITHUB_OUTPUT"
          else
            iphone_name="$(xcrun simctl list devices available | awk -F '[()]' '/iPhone/ { print $1; exit }' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
            if [ -z "$iphone_name" ]; then
              echo "error: no available iPhone simulator found" >&2
              exit 1
            fi
            echo "value=platform=iOS Simulator,name=${iphone_name},OS=latest" >> "$GITHUB_OUTPUT"
          fi

      - name: Build
        run: |
          cd apple
          xcodebuild \
            build \
            -project LinXApple.xcodeproj \
            -scheme LinXApple \
            -configuration Debug \
            -destination "${{ steps.destination.outputs.value }}"

      - name: Test
        run: |
          cd apple
          mkdir -p .asc/reports
          xcodebuild \
            test \
            -project LinXApple.xcodeproj \
            -scheme LinXApple \
            -configuration Debug \
            -destination "${{ steps.destination.outputs.value }}" \
            -resultBundlePath ".asc/reports/tests-${GITHUB_RUN_ID}.xcresult"

      - name: Upload test results
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: linxapple-test-results
          path: apple/.asc/reports/*.xcresult
          if-no-files-found: ignore

      - name: Upload logs
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: linxapple-build-test-logs
          path: apple/.asc/runs/*.log
          if-no-files-found: ignore
```

### 5.2 `.github/workflows/apple-testflight.yml`

```yaml
name: Apple TestFlight

on:
  workflow_run:
    workflows:
      - Apple Build and Test
    branches:
      - main
    types:
      - completed
  workflow_dispatch:
    inputs:
      version:
        description: "Marketing version. Leave empty to read MARKETING_VERSION from apple/project.yml."
        required: false
        type: string

concurrency:
  group: apple-testflight
  cancel-in-progress: false

jobs:
  testflight:
    name: Upload LinXApple to TestFlight
    runs-on: macos-latest
    timeout-minutes: 90
    if: >
      github.event_name == 'workflow_dispatch' ||
      github.event.workflow_run.conclusion == 'success'

    env:
      ASC_APP_ID: ${{ vars.LINX_APPLE_ASC_APP_ID }}
      TESTFLIGHT_GROUP: ${{ vars.LINX_APPLE_TESTFLIGHT_GROUP }}
      ASC_KEY_ID: ${{ secrets.ASC_KEY_ID }}
      ASC_ISSUER_ID: ${{ secrets.ASC_ISSUER_ID }}
      ASC_PRIVATE_KEY_P8_BASE64: ${{ secrets.ASC_PRIVATE_KEY_P8_BASE64 }}
      ASC_BYPASS_KEYCHAIN: "1"
      ASC_STRICT_AUTH: "true"
      CONFIRM: "1"

    steps:
      - name: Checkout workflow run commit
        if: github.event_name == 'workflow_run'
        uses: actions/checkout@v4
        with:
          ref: ${{ github.event.workflow_run.head_sha }}

      - name: Checkout manual ref
        if: github.event_name == 'workflow_dispatch'
        uses: actions/checkout@v4

      - name: Validate release environment
        run: |
          set -euo pipefail
          test -n "$ASC_APP_ID"
          test -n "$TESTFLIGHT_GROUP"
          test -n "$ASC_KEY_ID"
          test -n "$ASC_ISSUER_ID"
          test -n "$ASC_PRIVATE_KEY_P8_BASE64"

      - name: Install tools
        run: |
          if ! command -v xcodegen >/dev/null 2>&1; then
            brew install xcodegen
          fi
          if ! command -v asc >/dev/null 2>&1; then
            brew install asc
          fi

      - name: Cache Whisper artifacts
        uses: actions/cache@v4
        with:
          path: apple/.build/whisper
          key: whisper-v1.8.4-${{ runner.os }}

      - name: Cache SwiftPM and DerivedData
        uses: actions/cache@v4
        with:
          path: |
            ~/Library/Caches/org.swift.swiftpm
            ~/Library/Developer/Xcode/DerivedData
          key: apple-spm-deriveddata-${{ runner.os }}-${{ hashFiles('apple/LinXApple.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved') }}
          restore-keys: |
            apple-spm-deriveddata-${{ runner.os }}-

      - name: Resolve version
        run: |
          set -euo pipefail
          input_version="${{ inputs.version }}"
          if [ -n "$input_version" ]; then
            version="$input_version"
          else
            version="$(ruby -ryaml -e 'puts YAML.load_file("apple/project.yml").dig("settings", "base", "MARKETING_VERSION")')"
          fi
          if [ -z "$version" ]; then
            echo "error: VERSION is empty" >&2
            exit 1
          fi
          echo "VERSION=$version" >> "$GITHUB_ENV"

      - name: Configure asc authentication
        run: |
          set -euo pipefail
          mkdir -p apple/.asc/tmp
          printf '%s' "$ASC_PRIVATE_KEY_P8_BASE64" | base64 --decode > apple/.asc/tmp/AuthKey.p8
          chmod 600 apple/.asc/tmp/AuthKey.p8
          cat > apple/.asc/config.json <<EOF
          {
            "key_id": "$ASC_KEY_ID",
            "issuer_id": "$ASC_ISSUER_ID",
            "private_key_path": ".asc/tmp/AuthKey.p8",
            "app_id": "$ASC_APP_ID"
          }
          EOF

      - name: Prepare LinXApple
        run: |
          cd apple
          ./scripts/release-ios.sh prepare

      - name: Upload to TestFlight
        run: |
          cd apple
          ./scripts/release-ios.sh testflight

      - name: Upload release artifacts
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: linxapple-testflight-artifacts
          path: |
            apple/.asc/artifacts/*.ipa
            apple/.asc/artifacts/*.xcarchive
            apple/.asc/reports/*.xcresult
            apple/.asc/runs/*.log
          if-no-files-found: ignore
```

---

## 6. 使用方式 / API 示例（Usage）

### 6.1 配置 GitHub Variables

```text
LINX_APPLE_ASC_APP_ID=<App Store Connect app id>
LINX_APPLE_TESTFLIGHT_GROUP=<TestFlight group name>
```

### 6.2 配置 GitHub Secrets

```text
ASC_KEY_ID=<App Store Connect API key id>
ASC_ISSUER_ID=<App Store Connect issuer id>
ASC_PRIVATE_KEY_P8_BASE64=<base64 encoded AuthKey_XXXXXX.p8>
```

生成私钥 base64：

```sh
base64 -i AuthKey_XXXXXX.p8 | pbcopy
```

### 6.3 自动构建与测试

任意 PR 或 push 修改 `apple/**` 后，自动运行：

```text
Apple Build and Test
```

### 6.4 自动上传 TestFlight

当 `main` 分支上的 `Apple Build and Test` 成功完成后，自动运行：

```text
Apple TestFlight
```

### 6.5 手动上传 TestFlight

在 GitHub Actions 页面运行 `Apple TestFlight`，可选输入：

```text
version=0.1.1
```

留空时使用 `apple/project.yml` 中的 `MARKETING_VERSION`。

---

## 7. 注意事项 / 性能优化 / 扩展方向

### 7.1 注意事项

- `macos-latest` 是浮动 runner label，GitHub 可能变更默认 macOS/Xcode 版本。
- 如需完全可复现构建，后续把 runner 固定为 `macos-15` 或 `macos-26`。
- TestFlight workflow 不在 PR 上执行，避免 fork/PR 暴露发布路径。
- `ASC_PRIVATE_KEY_P8_BASE64` 只能放在 Secrets，不能提交到仓库。
- `apple/.asc/config.json` 和 `apple/.asc/tmp/` 已由 `.gitignore` 保护。
- `workflow_run` 触发时 checkout 必须使用 `head_sha`，保证发布的是已通过 build/test 的同一份代码。

### 7.2 性能优化

- Whisper 下载通过 `apple/.build/whisper` cache 加速。
- SwiftPM 和 DerivedData cache 用 `Package.resolved` hash 做 key，依赖变化时自动刷新。
- Build/Test workflow 使用 `concurrency` 取消同一 ref 的旧任务，减少 macOS runner 消耗。
- TestFlight workflow 不取消进行中的发布，避免中途取消导致 App Store Connect 状态不一致。

### 7.3 扩展方向

- 后续可把 TestFlight 发布从 `workflow_run` 调整为 tag 驱动，例如 `v*`。
- 后续可新增 `Apple App Store Release` workflow，复用 `./scripts/release-ios.sh appstore`。
- 后续可把 `SUBMIT_BETA_REVIEW` 暴露为 `workflow_dispatch` 输入，控制是否提交外部测试审核。
- 后续可将 `.xcresult` 接入测试报告解析，生成 PR comment。
