import { NativeModules } from 'react-native';

export interface LinxAppVersion {
  versionName: string;
  buildNumber: number;
}

export interface LinxUpdateManifest {
  latestVersion: string;
  latestBuild: number;
  minimumBuild?: number;
  downloadUrl: string;
  releaseNotes?: string;
}

export interface LinxAvailableUpdate {
  latestVersion: string;
  latestBuild: number;
  minimumBuild?: number;
  downloadUrl: string;
  releaseNotes?: string;
  required: boolean;
}

export const LINX_APP_VERSION: LinxAppVersion = {
  versionName: '1.0.1',
  buildNumber: 2,
};

export const DEFAULT_UPDATE_MANIFEST_URL = '';

interface NativeAppInfoModule {
  getVersion?: () => Promise<unknown>;
}

export function normalizeUpdateManifestUrl(value?: string | null): string | null {
  const trimmed = value?.trim();
  return trimmed ? trimmed : null;
}

export function getAvailableUpdate(
  manifest: LinxUpdateManifest | null | undefined,
  current: LinxAppVersion = LINX_APP_VERSION,
): LinxAvailableUpdate | null {
  if (!isValidManifest(manifest)) {
    return null;
  }
  if (manifest.latestBuild <= current.buildNumber) {
    return null;
  }
  return {
    latestVersion: manifest.latestVersion,
    latestBuild: manifest.latestBuild,
    ...(typeof manifest.minimumBuild === 'number' ? { minimumBuild: manifest.minimumBuild } : {}),
    downloadUrl: manifest.downloadUrl,
    ...(manifest.releaseNotes ? { releaseNotes: manifest.releaseNotes } : {}),
    required: typeof manifest.minimumBuild === 'number'
      ? current.buildNumber < manifest.minimumBuild
      : false,
  };
}

export async function fetchAvailableUpdate(input: {
  manifestUrl?: string | null;
  current?: LinxAppVersion;
  nativeAppInfo?: NativeAppInfoModule | null;
  fetchImpl?: typeof fetch;
}): Promise<LinxAvailableUpdate | null> {
  const manifestUrl = normalizeUpdateManifestUrl(input.manifestUrl ?? DEFAULT_UPDATE_MANIFEST_URL);
  if (!manifestUrl) {
    return null;
  }
  const fetcher = input.fetchImpl ?? fetch;
  const response = await fetcher(manifestUrl, {
    headers: { accept: 'application/json' },
  });
  if (!response.ok) {
    throw new Error(`Update manifest request failed: ${response.status}`);
  }
  const current = input.current ?? await getCurrentAppVersion(input.nativeAppInfo);
  return getAvailableUpdate(await response.json(), current);
}

export async function getCurrentAppVersion(
  nativeAppInfo: NativeAppInfoModule | null | undefined =
    NativeModules.LinxAppInfo as NativeAppInfoModule | undefined,
): Promise<LinxAppVersion> {
  if (!nativeAppInfo?.getVersion) {
    return LINX_APP_VERSION;
  }

  try {
    const version = await nativeAppInfo.getVersion();
    return normalizeNativeAppVersion(version) ?? LINX_APP_VERSION;
  } catch {
    return LINX_APP_VERSION;
  }
}

function normalizeNativeAppVersion(value: unknown): LinxAppVersion | null {
  const candidate = value as {
    versionName?: unknown;
    buildNumber?: unknown;
    versionCode?: unknown;
  };
  const buildNumber = typeof candidate?.buildNumber === 'number'
    ? candidate.buildNumber
    : candidate?.versionCode;
  if (
    typeof candidate?.versionName !== 'string' ||
    typeof buildNumber !== 'number' ||
    !Number.isFinite(buildNumber)
  ) {
    return null;
  }
  return {
    versionName: candidate.versionName,
    buildNumber,
  };
}

function isValidManifest(value: unknown): value is LinxUpdateManifest {
  return Boolean(value) &&
    typeof value === 'object' &&
    typeof (value as LinxUpdateManifest).latestVersion === 'string' &&
    typeof (value as LinxUpdateManifest).latestBuild === 'number' &&
    Number.isFinite((value as LinxUpdateManifest).latestBuild) &&
    typeof (value as LinxUpdateManifest).downloadUrl === 'string' &&
    (value as LinxUpdateManifest).downloadUrl.trim().length > 0;
}
