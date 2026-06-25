import { resolvePodBaseUrl } from '../linx/pod/paths';
import type { LinxAuthSession } from '../linx/types';
import {
  DEFAULT_SMOKE_RESOURCE_PATH_INPUT,
  deriveApiBaseUrlFromIdp,
  deriveNodeIdFromStorageUrl,
} from './deriveP2PSmokeTarget';
import type { P2PSmokeDefaults } from './P2PSmokeScreen';

export function p2pSmokeDefaultsFromSession(
  session: LinxAuthSession | null | undefined,
): P2PSmokeDefaults | undefined {
  if (!session) {
    return undefined;
  }

  const storageUrl = resolvePodBaseUrl({
    webId: session.webId,
    storageServerUrl: session.storageServerUrl,
  });

  return {
    idpUrl: session.issuerUrl,
    storageUrl,
    localSpUrl: storageUrl,
    apiBaseUrl: deriveApiBaseUrlFromIdp(session.issuerUrl),
    nodeId: deriveNodeIdFromStorageUrl(storageUrl),
    resourcePath: DEFAULT_SMOKE_RESOURCE_PATH_INPUT,
  };
}
