import { ensureTrailingSlash } from './utils';

export interface LinxLoginOptions {
  storageServerUrl?: string;
}

export function normalizeCustomStorageServerUrl(value?: string): string | undefined {
  const trimmed = value?.trim();
  if (!trimmed) {
    return undefined;
  }
  if (!/^https?:\/\//i.test(trimmed)) {
    throw new Error('Custom SP server must be an absolute http(s) URL.');
  }

  const parsed = new URL(trimmed);
  if (parsed.protocol !== 'http:' && parsed.protocol !== 'https:') {
    throw new Error('Custom SP server must be an absolute http(s) URL.');
  }
  if (parsed.pathname !== '/' && parsed.pathname !== '') {
    throw new Error('Custom SP server must not include a pod owner path.');
  }

  return ensureTrailingSlash(`${parsed.protocol}//${parsed.host}/`);
}
