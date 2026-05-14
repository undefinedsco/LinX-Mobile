export const LINX_CONTRACT = {
  appName: 'LinX Mobile',
  issuerOrigin: 'https://id.undefineds.co',
  runtimeCloudOrigin: 'https://api.undefineds.co',
  runtimeVersion: 'v1',
  redirectUrl: 'co.undefineds.linx.mobile://auth/callback',
  loginScopes: ['openid', 'offline_access', 'webid'],
  defaultModelId: 'linx-lite',
  fallbackModelIds: ['linx', 'linx-lite'],
  defaultChatId: 'mobile-default',
  defaultAgentId: 'linx-mobile-assistant',
  defaultChatTitle: 'LinX Mobile',
  defaultAgentName: 'LinX Mobile Assistant',
  defaultThreadTitle: 'Mobile Session',
  defaultThreadWorkspace: 'co.undefineds.linx.mobile://workspace/default',
  pageSize: 40,
  podRequestTimeoutMs: 20_000,
  runtimeRequestTimeoutMs: 10 * 60 * 1000,
  tokenRefreshLeewayMs: 60_000,
} as const;

export const LINX_NAMESPACE = {
  dcterms: 'http://purl.org/dc/terms/',
  foaf: 'http://xmlns.com/foaf/0.1/',
  meeting: 'http://www.w3.org/ns/pim/meeting#',
  schema: 'http://schema.org/',
  sioc: 'http://rdfs.org/sioc/ns#',
  udfs: 'https://undefineds.co/ns#',
  wf: 'http://www.w3.org/2005/01/wf/flow-1.0#',
  xsd: 'http://www.w3.org/2001/XMLSchema#',
} as const;

export const LINX_KEYCHAIN_SERVICE = 'co.undefineds.linx.mobile.session';

export const LINX_STORAGE_KEYS = {
  recentThreadId: '@linx-mobile/recent-thread-id',
} as const;
