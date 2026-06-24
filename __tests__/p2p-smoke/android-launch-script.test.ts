import { execFile } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { promisify } from 'node:util';

const execFileAsync = promisify(execFile);
const root = path.resolve(__dirname, '../..');

test('android p2p launcher dry-run prints install and prefilled start commands without requiring a device', async () => {
  const { stdout } = await execFileAsync('node', [
    'scripts/android-p2p-smoke-launch.js',
    '--dry-run',
    '--adb',
    '/opt/homebrew/bin/adb',
    '--adb-server-port',
    '5041',
    '--idp-url',
    'https://id.undefineds.co/',
    '--storage-url',
    'https://node-0000.undefineds.co/',
    '--client-id',
    'phone-1',
    '--resource-path',
    '/alice/.data/linx-mobile-p2p-smoke.txt',
  ], { cwd: root, timeout: 8_000 });

  expect(stdout).toContain('DRY RUN');
  expect(stdout).toContain('ANDROID_ADB_SERVER_PORT=5041');
  expect(stdout).toContain('/opt/homebrew/bin/adb install -r');
  expect(stdout).toContain('/opt/homebrew/bin/adb shell am start');
  expect(stdout).toContain('--es xpod.p2p.idpUrl https://id.undefineds.co/');
  expect(stdout).toContain('--es xpod.p2p.storageUrl https://node-0000.undefineds.co/');
  expect(stdout).toContain('--es xpod.p2p.clientId phone-1');
  expect(stdout).toContain('--es xpod.p2p.resourcePath /alice/.data/linx-mobile-p2p-smoke.txt');
});

test('android p2p launcher can dry-run result capture from the native log marker', async () => {
  const { stdout } = await execFileAsync('node', [
    'scripts/android-p2p-smoke-launch.js',
    '--dry-run',
    '--skip-build',
    '--skip-install',
    '--capture-result',
    'mobile-result.json',
    '--capture-timeout-ms',
    '90000',
    '--client-id',
    'phone-1',
  ], { cwd: root, timeout: 8_000 });

  expect(stdout).toContain('# build skipped by --skip-build');
  expect(stdout).toContain('# install skipped by --skip-install');
  expect(stdout).toContain('adb logcat -c');
  expect(stdout).toContain('adb shell am start');
  expect(stdout).toContain('# capture RESULT_JSON from XpodP2PSmoke into mobile-result.json within 90000ms');
  expect(stdout).toContain("adb logcat -v raw -s XpodP2PSmoke:I '*:S'");
});


test('android p2p launcher supports hdc transport for Harmony USB devices', async () => {
  const { stdout } = await execFileAsync('node', [
    'scripts/android-p2p-smoke-launch.js',
    '--dry-run',
    '--transport',
    'hdc',
    '--hdc',
    '/tmp/hdc',
    '--hdc-target',
    '62T0226101021775',
    '--skip-build',
    '--capture-result',
    'mobile-result.json',
    '--client-id',
    'phone-hdc',
  ], { cwd: root, timeout: 8_000 });

  expect(stdout).toContain('transport=hdc');
  expect(stdout).toContain('/tmp/hdc -t 62T0226101021775 install -r');
  expect(stdout).toContain('/tmp/hdc -t 62T0226101021775 hilog -r');
  expect(stdout).toContain('/tmp/hdc -t 62T0226101021775 hilog');
  expect(stdout).toContain('/tmp/hdc -t 62T0226101021775 shell am start');
  expect(stdout).toContain('--es xpod.p2p.clientId phone-hdc');
});

test('android p2p launcher exports a reusable RESULT_JSON parser for logcat capture', () => {
  const outputPath = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'linx-p2p-')), 'mobile-result.json');
  const { tryCaptureResultLine } = require('../../scripts/android-p2p-smoke-launch.js');

  expect(tryCaptureResultLine('noise', outputPath)).toBe(false);
  expect(tryCaptureResultLine(
    'XpodP2PSmoke RESULT_JSON {"smokeOk":true,"route":{"kind":"p2p"},"connectorEvents":[{"type":"success"}],"putStatus":201,"status":200}',
    outputPath,
  )).toBe(true);

  expect(JSON.parse(fs.readFileSync(outputPath, 'utf8'))).toEqual({
    smokeOk: true,
    route: { kind: 'p2p' },
    connectorEvents: [{ type: 'success' }],
    putStatus: 201,
    status: 200,
  });
});

test('android p2p launcher can prefill the local SP URL without changing the cloud IDP provider', async () => {
  const { stdout } = await execFileAsync('node', [
    'scripts/android-p2p-smoke-launch.js',
    '--dry-run',
    '--skip-build',
    '--skip-install',
    '--local-sp-url',
    'https://node-0000.undefineds.co/alice/',
    '--client-id',
    'phone-local',
  ], { cwd: root, timeout: 8_000 });

  expect(stdout).toContain('--es xpod.p2p.localSpUrl https://node-0000.undefineds.co/alice/');
  expect(stdout).toContain('--es xpod.p2p.idpUrl https://id.undefineds.co/');
  expect(stdout).toContain('--es xpod.p2p.clientId phone-local');
});
