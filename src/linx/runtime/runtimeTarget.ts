import { LINX_CONTRACT } from '../contract';
import { trimTrailingSlash } from '../utils';

const CLOUD_IDENTITY_HOSTS = new Set(['id.undefineds.co']);

export function resolveRuntimeOriginForIssuerUrl(issuerUrl: string): string {
  const normalized = trimTrailingSlash(issuerUrl || LINX_CONTRACT.issuerOrigin);
  try {
    const parsed = new URL(normalized);
    if (CLOUD_IDENTITY_HOSTS.has(parsed.hostname)) {
      return LINX_CONTRACT.runtimeCloudOrigin;
    }
  } catch {
    return LINX_CONTRACT.runtimeCloudOrigin;
  }
  return normalized;
}

export function resolveRuntimeApiBaseUrl(runtimeOriginOrBase: string): string {
  const normalized = trimTrailingSlash(
    runtimeOriginOrBase || LINX_CONTRACT.runtimeCloudOrigin,
  );
  return normalized.endsWith(`/${LINX_CONTRACT.runtimeVersion}`)
    ? normalized
    : `${normalized}/${LINX_CONTRACT.runtimeVersion}`;
}

export function resolveRuntimeApiBaseUrlForIssuerUrl(issuerUrl: string): string {
  return resolveRuntimeApiBaseUrl(resolveRuntimeOriginForIssuerUrl(issuerUrl));
}
