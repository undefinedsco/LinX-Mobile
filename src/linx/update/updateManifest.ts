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
  return getAvailableUpdate(await response.json(), input.current ?? LINX_APP_VERSION);
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
