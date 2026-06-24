import fs from 'fs';
import path from 'path';
import {
  LINX_APP_VERSION,
  getAvailableUpdate,
  normalizeUpdateManifestUrl,
  type LinxUpdateManifest,
} from '../src/linx/update/updateManifest';

const root = path.resolve(__dirname, '..');

function read(relativePath: string): string {
  return fs.readFileSync(path.join(root, relativePath), 'utf8');
}

test('detects a newer app build from an update manifest', () => {
  const manifest: LinxUpdateManifest = {
    latestVersion: '1.0.1',
    latestBuild: LINX_APP_VERSION.buildNumber + 1,
    minimumBuild: LINX_APP_VERSION.buildNumber,
    downloadUrl: 'https://downloads.undefineds.co/linx-mobile/latest',
    releaseNotes: 'P2P smoke validation build.',
  };

  expect(getAvailableUpdate(manifest, LINX_APP_VERSION)).toEqual({
    latestVersion: '1.0.1',
    latestBuild: LINX_APP_VERSION.buildNumber + 1,
    minimumBuild: LINX_APP_VERSION.buildNumber,
    downloadUrl: 'https://downloads.undefineds.co/linx-mobile/latest',
    releaseNotes: 'P2P smoke validation build.',
    required: false,
  });
});

test('does not prompt when manifest is missing or not newer', () => {
  expect(getAvailableUpdate(null, LINX_APP_VERSION)).toBeNull();
  expect(getAvailableUpdate({
    latestVersion: LINX_APP_VERSION.versionName,
    latestBuild: LINX_APP_VERSION.buildNumber,
    downloadUrl: 'https://downloads.undefineds.co/linx-mobile/latest',
  }, LINX_APP_VERSION)).toBeNull();
});

test('normalizes empty update manifest config as disabled', () => {
  expect(normalizeUpdateManifestUrl(undefined)).toBeNull();
  expect(normalizeUpdateManifestUrl('   ')).toBeNull();
  expect(normalizeUpdateManifestUrl('https://downloads.undefineds.co/linx-mobile/update.json')).toBe(
    'https://downloads.undefineds.co/linx-mobile/update.json',
  );
});

test('product and p2p smoke entries mount automatic update prompt', () => {
  expect(read('App.tsx')).toContain('UpdatePrompt');
  expect(read('src/p2p-smoke/P2PSmokeApp.tsx')).toContain('UpdatePrompt');
  expect(read('src/linx/update/UpdatePrompt.tsx')).toContain('New LinX Mobile version available');
});


test('readme documents the update manifest prompt', () => {
  const readme = read('README.md');
  expect(readme).toContain('Automatic update prompt');
  expect(readme).toContain('latestBuild');
  expect(readme).toContain('--update-manifest-url');
});
