import fs from 'fs';
import path from 'path';

const root = path.resolve(__dirname, '../..');

function read(relativePath: string): string {
  return fs.readFileSync(path.join(root, relativePath), 'utf8');
}

test('keeps product app entry while adding a separate p2pSmoke package', () => {
  const buildGradle = read('android/app/build.gradle');
  expect(buildGradle).toContain('p2pSmoke {');
  expect(buildGradle).toContain('applicationIdSuffix ".p2psmoke"');
  expect(buildGradle).toContain('matchingFallbacks = ["debug"]');

  const productApp = read('App.tsx');
  expect(productApp).toContain('useLinxChatApp');
});

test('product chat embeds p2p smoke so the single pgyer product package can validate p2p', () => {
  const chatScreen = read('src/linx/ui/ChatScreen.tsx');
  const threadSheet = read('src/linx/ui/ThreadListSheet.tsx');
  const pgyerWorkflow = read('.github/workflows/android-pgyer.yml');

  expect(chatScreen).toContain('P2PSmokeScreen');
  expect(chatScreen).toContain('p2pSmokeDefaultsFromSession');
  expect(threadSheet).toContain('open-p2p-smoke-button');
  expect(pgyerWorkflow).toContain(':app:assembleProductRelease');
  expect(pgyerWorkflow).toContain('android/app/build/outputs/apk/product/release');
});

test('p2p smoke package has its own RN entry and native tcp bridge', () => {
  expect(read('index.js')).toContain('LinXP2PSmoke');
  expect(read('src/p2p-smoke/P2PSmokeApp.tsx')).toContain('P2PSmokeScreen');
  expect(read('android/app/src/product/java/com/linxmobile/MainActivity.kt')).toContain(
    'LinXMobile',
  );
  expect(read('android/app/src/p2pSmoke/java/com/linxmobile/MainActivity.kt')).toContain(
    'LinXP2PSmoke',
  );
  expect(read('android/app/src/main/java/com/linxmobile/MainApplication.kt')).toContain(
    'XpodP2PSmokePackage()',
  );
  expect(read('android/app/src/main/java/com/linxmobile/p2p/XpodP2PSmokeModule.kt')).toContain(
    'Socket()',
  );
  expect(read('android/app/src/main/java/com/linxmobile/p2p/XpodP2PSmokeModule.kt')).toContain(
    'xpod-p2p-http/1',
  );
});

test('ios host exposes the same XpodP2PSmoke native tcp bridge for apple phone validation', () => {
  const module = read('ios/LinXMobile/XpodP2PSmokeModule.swift');
  const bridge = read('ios/LinXMobile/XpodP2PSmokeModuleBridge.m');
  const appDelegate = read('ios/LinXMobile/AppDelegate.swift');
  const project = read('ios/LinXMobile.xcodeproj/project.pbxproj');

  expect(module).toContain('@objc(XpodP2PSmoke)');
  expect(bridge).toContain('RCTPromiseResolveBlock');
  expect(module).toContain('NWConnection');
  expect(module).toContain('xpod-p2p-http/1');
  expect(module).toContain('createSession');
  expect(module).toContain('waitForRemoteCandidates');
  expect(module).toContain('setSocketTimeouts');
  expect(module).toContain('SO_RCVTIMEO');
  expect(module).toContain('SO_SNDTIMEO');
  expect(appDelegate).toContain('--p2p-smoke');
  expect(appDelegate).toContain('LinXP2PSmoke');
  expect(bridge).toContain('RCT_EXTERN_MODULE(XpodP2PSmoke');
  expect(bridge).toContain('RCT_EXTERN_METHOD(run:');
  expect(project).toContain('XpodP2PSmokeModule.swift in Sources');
  expect(project).toContain('XpodP2PSmokeModuleBridge.m in Sources');
});

test('ios native bridge races compatible raw tcp candidate pairs', () => {
  const module = read('ios/LinXMobile/XpodP2PSmokeModule.swift');

  expect(module).toContain('DispatchGroup');
  expect(module).toContain('NSLock');
  expect(module).toContain('firstSuccessOrAllDone');
  expect(module).toContain('DispatchQueue.global');
  expect(module).toContain('_ = group.wait(timeout: .now() + .milliseconds(winnerSelectionWindowMs))');
  expect(module).not.toContain('shouldStop = hasSuccess');
});

test('p2p smoke UI keeps user-facing configuration to IDP and SP', () => {
  const screen = read('src/p2p-smoke/P2PSmokeScreen.tsx');
  expect(screen).toContain('IDP');
  expect(screen).toContain('SP');
  expect(screen).toContain('Client ID');
  expect(screen).toContain('Resource path');
  expect(screen).not.toContain('Signal token');
  expect(screen).not.toContain('setToken');
  expect(screen).not.toContain('localPort');
  expect(screen).not.toContain('remotePort');
  expect(screen).not.toContain('candidateId');
  expect(screen).not.toContain('Client public host');
});

test('readme documents login-derived token and Xcode true-device validation', () => {
  const readme = read('README.md');

  expect(readme).toContain('Login to IDP');
  expect(readme).toContain('Xcode');
  expect(readme).toContain('true iPhone device');
  expect(readme).toContain('Simulator is not final P2P acceptance evidence');
  expect(readme).toContain('--api-base-url https://api.undefineds.co/');
  expect(readme).not.toContain('--api-base-url https://id.undefineds.co/');
  expect(readme).not.toContain('temporary signal token');
  expect(readme).not.toContain('Signal token');
});

test('android build resolves AsyncStorage shared storage from the package local repo', () => {
  const rootBuildGradle = read('android/build.gradle');
  expect(rootBuildGradle).toContain('@react-native-async-storage/async-storage/android/local_repo');
});

test('native bridge attempts compatible candidate pairs instead of only the first port', () => {
  const module = read('android/app/src/main/java/com/linxmobile/p2p/XpodP2PSmokeModule.kt');
  expect(module).toContain('compatibleLocalCandidates');
  expect(module).toContain('compatibleRemoteCandidates');
  expect(module).toContain('for (remoteCandidate in remoteCandidates)');
  expect(module).toContain('for (localCandidate in localCandidates)');
});

test('native bridge uses signal-enriched local candidates after session creation', () => {
  const module = read('android/app/src/main/java/com/linxmobile/p2p/XpodP2PSmokeModule.kt');
  expect(module).toContain('compatibleLocalCandidatesFromSessionOrFallback');
  expect(module).toContain('session.optJSONArray("candidates")');
  expect(module).toContain('candidate.optString("sourceId") == clientId');
  expect(module).toContain('clientAddressEvidence(connection.localCandidate)');
});

test('native bridge resolves failure evidence after signal session creation', () => {
  const module = read('android/app/src/main/java/com/linxmobile/p2p/XpodP2PSmokeModule.kt');
  expect(module).toContain('var stage = "create-session"');
  expect(module).toContain('var sessionId: String? = null');
  expect(module).toContain('putString("stage", stage)');
  expect(module).toContain('putString("sessionId", sessionId)');
  expect(module).toContain('putString("error"');
});


test('android native connector events are collected off the React Native WritableArray from worker threads', () => {
  const module = read('android/app/src/main/java/com/linxmobile/p2p/XpodP2PSmokeModule.kt');

  expect(module).toContain('val connectorEventJson = Collections.synchronizedList(mutableListOf<JSONObject>())');
  expect(module).toContain('appendConnectorEvents(connectorEvents, connectorEventJson)');
  expect(module).toContain('private fun event(type: String, localPort: Int, remotePort: Int, message: String?): JSONObject');
  expect(module).not.toContain('events.pushMap(event(');
});

test('native smoke success requires both PUT and GET responses to be 2xx', () => {
  const android = read('android/app/src/main/java/com/linxmobile/p2p/XpodP2PSmokeModule.kt');
  const ios = read('ios/LinXMobile/XpodP2PSmokeModule.swift');

  expect(android).toContain('val putStatus = putResponse.optInt("status", 0)');
  expect(android).toContain('putBoolean("smokeOk", putStatus in 200..299 && status in 200..299)');
  expect(ios).toContain('let putStatus = putResponse.int("status") ?? 0');
  expect(ios).toContain('"smokeOk": (200...299).contains(putStatus) && (200...299).contains(status)');
});

test('android native smoke writes verifier evidence to a logcat RESULT_JSON marker', () => {
  const module = read('android/app/src/main/java/com/linxmobile/p2p/XpodP2PSmokeModule.kt');

  expect(module).toContain('import android.util.Log');
  expect(module).toContain('private const val RESULT_MARKER = "RESULT_JSON "');
  expect(module).toContain('Log.i(LOG_TAG, RESULT_MARKER + verifierEvidenceJson(result))');
  expect(module).toContain('private fun verifierEvidenceJson(result: ReadableMap): String');
  expect(module).toContain('successConnectorEvents(result.getArray("connectorEvents"))');
  expect(module).not.toContain('readableMapToJson(result).toString()');
});

test('ios native smoke writes verifier evidence to an Xcode console RESULT_JSON marker', () => {
  const module = read('ios/LinXMobile/XpodP2PSmokeModule.swift');

  expect(module).toContain('private let resultMarker = "RESULT_JSON "');
  expect(module).toContain('NSLog("XpodP2PSmoke %@%@", resultMarker, verifierEvidenceJson(result))');
  expect(module).toContain('private func verifierEvidenceJson(_ result: [String: Any]) -> String');
  expect(module).toContain('successConnectorEvents(result["connectorEvents"] as? [[String: Any]] ?? [])');
});

test('readme documents that mobile smoke validates both write and read status', () => {
  const readme = read('README.md');

  expect(readme).toContain('putStatus');
  expect(readme).toContain('PUT and GET');
});



test('android smoke launcher passes fields through intent extras', () => {
  const activity = read('android/app/src/p2pSmoke/java/com/linxmobile/MainActivity.kt');
  const screen = read('src/p2p-smoke/P2PSmokeScreen.tsx');
  const launcher = read('scripts/android-p2p-smoke-launch.js');
  const pkg = read('package.json');

  expect(activity).toContain('getLaunchOptions');
  expect(activity).toContain('p2pSmokeDefaults');
  expect(activity).toContain('xpod.p2p.idpUrl');
  expect(activity).toContain('xpod.p2p.storageUrl');
  expect(activity).toContain('xpod.p2p.clientId');
  expect(activity).toContain('xpod.p2p.resourcePath');
  expect(screen).toContain('initialSmokeDefaults');
  expect(screen).toContain('initialSmokeDefaults?.idpUrl');
  expect(launcher).toContain("'am'");
  expect(launcher).toContain("'start'");
  expect(launcher).toContain("'--es'");
  expect(launcher).toContain("'xpod.p2p.idpUrl'");
  expect(launcher).toContain("'xpod.p2p.storageUrl'");
  expect(launcher).toContain("'xpod.p2p.clientId'");
  expect(launcher).toContain("'xpod.p2p.resourcePath'");
  expect(pkg).toContain('p2p:android:launch');
});
