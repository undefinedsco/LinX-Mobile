import {
  deriveApiBaseUrlFromIdp,
  deriveNodeIdFromStorageUrl,
  normalizeResourcePath,
  resolveSmokeResourceUrl,
} from '../../src/p2p-smoke/deriveP2PSmokeTarget';
import { buildP2PSmokeRequest } from '../../src/p2p-smoke/p2pSmokeRequest';

test('derives xpod api origin from the configured IDP', () => {
  expect(deriveApiBaseUrlFromIdp('https://id.undefineds.co/')).toBe(
    'https://api.undefineds.co/',
  );
  expect(deriveApiBaseUrlFromIdp('https://id.example.test')).toBe(
    'https://api.example.test/',
  );
});

test('derives node id from the SP storage host', () => {
  expect(deriveNodeIdFromStorageUrl('https://node-0000.undefineds.co/alice/')).toBe(
    'node-0000',
  );
  expect(deriveNodeIdFromStorageUrl('https://alice.localhost:3000/')).toBe('alice');
});

test('resolves a canonical smoke resource inside the SP', () => {
  expect(normalizeResourcePath('a.txt')).toBe('/a.txt');
  expect(
    resolveSmokeResourceUrl({
      storageUrl: 'https://node-0000.undefineds.co/alice/',
      resourcePath: '.data/linx-mobile-p2p-smoke.txt',
    }),
  ).toBe('https://node-0000.undefineds.co/alice/.data/linx-mobile-p2p-smoke.txt');
});


test('builds port-only raw tcp candidates so signal can inject observed address', () => {
  const request = buildP2PSmokeRequest({
    idpUrl: 'https://id.undefineds.co/',
    storageUrl: 'https://node-0000.undefineds.co/alice/',
    clientId: 'device-1',
  });

  expect(request.localCandidates.length).toBeGreaterThan(0);
  for (const candidate of request.localCandidates) {
    expect(candidate.transport).toBe('raw-tcp-hole-punch');
    expect(candidate.port).toEqual(expect.any(Number));
    expect(candidate.host).toBeUndefined();
    expect(candidate.address).toBeUndefined();
    expect(candidate.url).toBeUndefined();
  }
});

test('uses caller-provided client id for coordinated manual acceptance', () => {
  const request = buildP2PSmokeRequest({
    idpUrl: 'https://id.undefineds.co/',
    storageUrl: 'https://node-0000.undefineds.co/alice/',
    clientId: 'phone-manual-1',
  });

  expect(request.clientId).toBe('phone-manual-1');
  expect(request.signalSessionsUrl).toBe('https://api.undefineds.co/v1/signal/nodes/node-0000/sessions');
  expect(request.targetUrl).toBe('https://node-0000.undefineds.co/alice/.data/linx-mobile-p2p-smoke.txt');
});


test('runP2PSmoke obtains bearer token from the mobile auth session when token is not provided', async () => {
  jest.resetModules();
  const nativeRun = jest.fn(async request => ({
    smokeOk: true,
    route: { kind: 'p2p' },
    connectorEvents: [],
    observedAuthorization: request.headers.authorization,
    observedToken: request.token,
  }));

  jest.doMock('react-native', () => ({
    Platform: { OS: 'android' },
    NativeModules: {
      XpodP2PSmoke: { run: nativeRun },
    },
  }));
  const authConstructor = jest.fn().mockImplementation(() => ({
    getAccessToken: jest.fn(async () => 'solid-access-token'),
    expireSession: jest.fn(async () => undefined),
  }));
  jest.doMock('../../src/linx/auth/oidc', () => ({
    LinxAuthController: authConstructor,
  }));

  const { runP2PSmoke } = require('../../src/p2p-smoke/mobileP2PSmoke');
  const evidence = await runP2PSmoke({
    idpUrl: 'https://id.undefineds.co/',
    storageUrl: 'https://node-0000.undefineds.co/alice/',
    clientId: 'phone-session-token',
  });

  expect(nativeRun).toHaveBeenCalledTimes(1);
  expect(nativeRun.mock.calls[0][0].headers.authorization).toBe('Bearer solid-access-token');
  expect(nativeRun.mock.calls[0][0].token).toBe('solid-access-token');
  expect(evidence.observedAuthorization).toBe('Bearer solid-access-token');
  expect(authConstructor).toHaveBeenCalledWith({
    issuerOrigin: 'https://id.undefineds.co/',
    redirectUrl: 'co.undefineds.linx.mobile.p2psmoke://auth/callback',
  });
});

test('p2p smoke screen lets the user login through IDP before running smoke', () => {
  const screen = readSource('src/p2p-smoke/P2PSmokeScreen.tsx');
  expect(screen).toContain('createP2PSmokeAuthController(idpUrl)');
  expect(screen).toContain('.login({ storageServerUrl })');
  expect(screen).toContain('Login to IDP');
  expect(screen).toContain('session?.webId');
});

test('p2p smoke screen can share verifier-ready result JSON', () => {
  const screen = readSource('src/p2p-smoke/P2PSmokeScreen.tsx');
  expect(screen).toContain('Share');
  expect(screen).toContain('formatP2PSmokeEvidenceForShare(result)');
  expect(screen).toContain('Share result JSON');
});

test('formats mobile smoke evidence as stable JSON for verifier handoff', () => {
  jest.resetModules();
  jest.doMock('react-native', () => ({
    Platform: { OS: 'android' },
    NativeModules: {},
  }));
  jest.doMock('../../src/linx/auth/oidc', () => ({
    LinxAuthController: jest.fn(),
  }));

  const { formatP2PSmokeEvidenceForShare } = require('../../src/p2p-smoke/mobileP2PSmoke');

  expect(formatP2PSmokeEvidenceForShare({
    smokeOk: true,
    route: { kind: 'p2p', id: 'p2p-raw-tcp' },
    connectorEvents: [{ type: 'success', localPort: 41001, remotePort: 42001 }],
  })).toBe([
    '{',
    '  "smokeOk": true,',
    '  "route": {',
    '    "kind": "p2p",',
    '    "id": "p2p-raw-tcp"',
    '  },',
    '  "connectorEvents": [',
    '    {',
    '      "type": "success",',
    '      "localPort": 41001,',
    '      "remotePort": 42001',
    '    }',
    '  ]',
    '}',
  ].join('\n'));
});

function readSource(relativePath: string): string {
  const fs = require('fs');
  const path = require('path');
  return fs.readFileSync(path.join(__dirname, '../..', relativePath), 'utf8');
}

test('runP2PSmoke preserves explicit token injection for automation', async () => {
  jest.resetModules();
  const nativeRun = jest.fn(async request => ({
    smokeOk: true,
    route: { kind: 'p2p' },
    connectorEvents: [],
    observedAuthorization: request.headers.authorization,
    observedToken: request.token,
  }));
  const getAccessToken = jest.fn(async () => 'solid-access-token');

  jest.doMock('react-native', () => ({
    Platform: { OS: 'android' },
    NativeModules: {
      XpodP2PSmoke: { run: nativeRun },
    },
  }));
  jest.doMock('../../src/linx/auth/oidc', () => ({
    LinxAuthController: jest.fn().mockImplementation(() => ({
      getAccessToken,
      expireSession: jest.fn(async () => undefined),
    })),
  }));

  const { runP2PSmoke } = require('../../src/p2p-smoke/mobileP2PSmoke');
  await runP2PSmoke({
    idpUrl: 'https://id.undefineds.co/',
    storageUrl: 'https://node-0000.undefineds.co/alice/',
    clientId: 'phone-automation-token',
    token: 'automation-token',
  });

  expect(getAccessToken).not.toHaveBeenCalled();
  expect(nativeRun.mock.calls[0][0].headers.authorization).toBe('Bearer automation-token');
  expect(nativeRun.mock.calls[0][0].token).toBe('automation-token');
});

test('derives smoke defaults from a user-deployed SP server root and cloud WebID', () => {
  const { deriveP2PSmokeDefaultsFromLocalSpServerRoot } = require('../../src/p2p-smoke/deriveP2PSmokeTarget');

  expect(deriveP2PSmokeDefaultsFromLocalSpServerRoot({
    localSpServerUrl: 'https://node-0000.undefineds.co/',
    webId: 'https://id.undefineds.co/alice/profile/card#me',
  })).toEqual({
    idpUrl: 'https://id.undefineds.co/',
    storageUrl: 'https://node-0000.undefineds.co/alice/',
    localSpUrl: 'https://node-0000.undefineds.co/',
    apiBaseUrl: 'https://api.undefineds.co/',
    nodeId: 'node-0000',
    resourcePath: '.data/linx-mobile-p2p-smoke.txt',
  });
});

test('rejects a pod path in the local SP server root', () => {
  const { deriveP2PSmokeDefaultsFromLocalSpServerRoot } = require('../../src/p2p-smoke/deriveP2PSmokeTarget');

  expect(() => deriveP2PSmokeDefaultsFromLocalSpServerRoot({
    localSpServerUrl: 'https://node-0000.undefineds.co/alice/',
    webId: 'https://id.undefineds.co/alice/profile/card#me',
  })).toThrow('SP server root must not include a pod path');
});

test('derives embedded smoke defaults from the current chat session', () => {
  const { p2pSmokeDefaultsFromSession } = require('../../src/p2p-smoke/p2pSmokeDefaultsFromSession');

  expect(p2pSmokeDefaultsFromSession({
    issuerUrl: 'https://id.undefineds.co/',
    clientId: 'client',
    webId: 'https://id.undefineds.co/alice/profile/card#me',
    accessToken: 'token',
    refreshToken: 'refresh',
    accessTokenExpirationDate: '2099-01-01T00:00:00.000Z',
    storageServerUrl: 'https://node-0000.undefineds.co/',
  })).toEqual({
    idpUrl: 'https://id.undefineds.co/',
    storageUrl: 'https://node-0000.undefineds.co/alice/',
    localSpUrl: 'https://node-0000.undefineds.co/',
    apiBaseUrl: 'https://api.undefineds.co/',
    nodeId: 'node-0000',
    resourcePath: '.data/linx-mobile-p2p-smoke.txt',
  });
});

test('rejects unsupported user-in-host shorthand for local SP server root', () => {
  const { deriveP2PSmokeDefaultsFromLocalSpServerRoot } = require('../../src/p2p-smoke/deriveP2PSmokeTarget');

  expect(() => deriveP2PSmokeDefaultsFromLocalSpServerRoot({
    localSpServerUrl: 'alice.node-0000.undefineds.co',
    webId: 'https://id.undefineds.co/alice/profile/card#me',
  })).toThrow(
    'user-in-host shorthand is not supported',
  );
});

test('p2p smoke screen exposes local SP server root input and applies derived fields', () => {
  const screen = readSource('src/p2p-smoke/P2PSmokeScreen.tsx');
  expect(screen).toContain('Local SP server root');
  expect(screen).toContain('deriveP2PSmokeDefaultsFromLocalSpServerRoot');
  expect(screen).toContain('Apply local SP');
  expect(screen).toContain('apiBaseUrl');
  expect(screen).toContain('nodeId');
  expect(screen).toContain('Cloud IDP provider');
});
