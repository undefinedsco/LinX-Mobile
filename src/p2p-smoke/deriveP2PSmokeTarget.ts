import { resolvePodBaseUrl } from '../linx/pod/paths';
import { ensureTrailingSlash } from '../linx/utils';

const DEFAULT_SMOKE_RESOURCE_PATH = '/.data/linx-mobile-p2p-smoke.txt';
export const DEFAULT_SMOKE_RESOURCE_PATH_INPUT = '.data/linx-mobile-p2p-smoke.txt';

export interface P2PSmokeDerivedDefaults {
  idpUrl: string;
  storageUrl: string;
  localSpUrl: string;
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

export function deriveP2PSmokeDefaultsFromLocalSpServerRoot(
  input: {
    localSpServerUrl: string;
    webId?: string;
  },
): P2PSmokeDerivedDefaults {
  const localSpUrl = parseLocalSpServerRoot(input.localSpServerUrl);
  const idpUrl = 'https://id.undefineds.co/';
  const storageUrl = input.webId
    ? resolvePodBaseUrl({
      webId: input.webId,
      storageServerUrl: localSpUrl,
    })
    : localSpUrl;

  return {
    idpUrl,
    storageUrl,
    localSpUrl,
    apiBaseUrl: deriveApiBaseUrlFromIdp(idpUrl),
    nodeId: deriveNodeIdFromStorageUrl(localSpUrl),
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

function parseLocalSpServerRoot(value: string): string {
  const trimmed = value.trim();
  if (!trimmed) {
    throw new Error('Local SP server root is required.');
  }
  if (!/^https?:\/\//i.test(trimmed)) {
    throw new Error(
      'Local SP server root must be an absolute http(s) URL like https://node-0000.undefineds.co/; user-in-host shorthand is not supported.',
    );
  }
  const parsed = new URL(trimmed);
  if (parsed.protocol !== 'http:' && parsed.protocol !== 'https:') {
    throw new Error('Local SP server root must be an absolute http(s) URL.');
  }
  if (parsed.pathname !== '/' && parsed.pathname !== '') {
    throw new Error(
      'SP server root must not include a pod path; pod base is resolved from WebID after login.',
    );
  }
  return ensureTrailingSlash(`${parsed.protocol}//${parsed.host}/`);
}
