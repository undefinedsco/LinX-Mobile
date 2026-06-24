const DEFAULT_SMOKE_RESOURCE_PATH = '/.data/linx-mobile-p2p-smoke.txt';
export const DEFAULT_SMOKE_RESOURCE_PATH_INPUT = '.data/linx-mobile-p2p-smoke.txt';

export interface P2PSmokeDerivedDefaults {
  idpUrl: string;
  storageUrl: string;
  apiBaseUrl: string;
  nodeId: string;
  resourcePath: string;
}

export function deriveApiBaseUrlFromIdp(idpUrl: string): string {
  const idp = new URL(ensureTrailingSlash(idpUrl));
  const labels = idp.hostname.split('.');
  if (labels[0] === 'id' && labels.length > 1) {
    labels[0] = 'api';
    return `${idp.protocol}//${labels.join('.')}/`;
  }
  return `${idp.protocol}//api.${idp.hostname}/`;
}

export function deriveNodeIdFromStorageUrl(storageUrl: string): string {
  const storage = new URL(storageUrl);
  const firstLabel = storage.hostname.split('.')[0];
  if (!firstLabel) {
    throw new Error(`Cannot derive nodeId from storage URL: ${storageUrl}`);
  }
  return firstLabel;
}

export function deriveP2PSmokeDefaultsFromLocalStorageUrl(
  localStorageUrl: string,
): P2PSmokeDerivedDefaults {
  const storage = parseLocalStorageUrl(localStorageUrl);
  const idpUrl = 'https://id.undefineds.co/';
  return {
    idpUrl,
    storageUrl: storage.url,
    apiBaseUrl: deriveApiBaseUrlFromIdp(idpUrl),
    nodeId: deriveNodeIdFromStorageUrl(storage.url),
    resourcePath: DEFAULT_SMOKE_RESOURCE_PATH_INPUT,
  };
}

export function normalizeResourcePath(resourcePath?: string): string {
  const trimmed = resourcePath?.trim() || DEFAULT_SMOKE_RESOURCE_PATH;
  return trimmed.startsWith('/') ? trimmed : `/${trimmed}`;
}

export function resolveSmokeResourceUrl(input: {
  storageUrl: string;
  resourcePath?: string;
}): string {
  const storage = new URL(ensureTrailingSlash(input.storageUrl));
  const path = normalizeResourcePath(input.resourcePath);
  const basePath = storage.pathname.endsWith('/')
    ? storage.pathname.slice(0, -1)
    : storage.pathname;
  const normalizedPath = `${basePath}${path}`.replace(/\/+/g, '/');
  return `${storage.origin}${normalizedPath}`;
}

export function ensureTrailingSlash(value: string): string {
  return value.endsWith('/') ? value : `${value}/`;
}

function parseLocalStorageUrl(value: string): { url: string } {
  const trimmed = value.trim();
  if (!trimmed) {
    throw new Error('Local SP URL is required.');
  }
  if (!/^https?:\/\//i.test(trimmed)) {
    throw new Error(
      'Local SP URL must be an absolute http(s) URL like https://node-0000.undefineds.co/alice/; user-in-host shorthand is not supported.',
    );
  }
  const parsed = new URL(trimmed);
  if (parsed.protocol !== 'http:' && parsed.protocol !== 'https:') {
    throw new Error('Local SP URL must be an absolute http(s) URL.');
  }
  const pathSegments = parsed.pathname.split('/').filter(Boolean);
  if (pathSegments.length === 0) {
    throw new Error('Local SP URL must include the pod owner as the first path segment.');
  }
  return { url: `${parsed.protocol}//${parsed.host}/${pathSegments[0]}/` };
}
