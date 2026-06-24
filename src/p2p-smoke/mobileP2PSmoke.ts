import { NativeModules, Platform } from 'react-native';
import { LinxAuthController } from '../linx/auth/oidc';
import {
  buildP2PSmokeRequest,
  type NativeP2PSmokeRequest,
  type P2PSmokeInput,
} from './p2pSmokeRequest';

export type { NativeP2PSmokeRequest, P2PSmokeInput } from './p2pSmokeRequest';
export { buildP2PSmokeRequest } from './p2pSmokeRequest';

export interface P2PSmokeEvidence {
  smokeOk: boolean;
  route: { kind: string; id?: string; [key: string]: unknown };
  status?: number;
  body?: string;
  connectorEvents: Array<{ type: string; localPort?: number; remotePort?: number; message?: string }>;
  [key: string]: unknown;
}

interface NativeP2PSmokeModule {
  run(request: NativeP2PSmokeRequest): Promise<P2PSmokeEvidence>;
}

const ANDROID_P2P_SMOKE_REDIRECT_URL = 'co.undefineds.linx.mobile.p2psmoke://auth/callback';
const IOS_P2P_SMOKE_REDIRECT_URL = 'co.undefineds.linx.mobile://auth/callback';

export async function runP2PSmoke(input: P2PSmokeInput): Promise<P2PSmokeEvidence> {
  const nativeModule = NativeModules.XpodP2PSmoke as NativeP2PSmokeModule | undefined;
  if (!nativeModule?.run) {
    throw new Error('XpodP2PSmoke native module is not available on this platform.');
  }
  const token = input.token ?? await createP2PSmokeAuthController(input.idpUrl).getAccessToken(false);
  return normalizeP2PSmokeEvidence(
    await nativeModule.run(buildP2PSmokeRequest({
      ...input,
      token,
    })),
  );
}

export function createP2PSmokeAuthController(idpUrl: string): LinxAuthController {
  return new LinxAuthController({
    issuerOrigin: idpUrl,
    redirectUrl: Platform.OS === 'android'
      ? ANDROID_P2P_SMOKE_REDIRECT_URL
      : IOS_P2P_SMOKE_REDIRECT_URL,
  });
}

export function normalizeP2PSmokeEvidence(value: unknown): P2PSmokeEvidence {
  const record = isRecord(value) ? value : {};
  const route = isRecord(record.route) ? record.route : {};
  const connectorEvents = Array.isArray(record.connectorEvents)
    ? record.connectorEvents.filter(isRecord).map(event => ({
      type: String(event.type ?? 'unknown'),
      ...(typeof event.localPort === 'number' ? { localPort: event.localPort } : {}),
      ...(typeof event.remotePort === 'number' ? { remotePort: event.remotePort } : {}),
      ...(typeof event.message === 'string' ? { message: event.message } : {}),
    }))
    : [];
  return {
    ...record,
    smokeOk: record.smokeOk === true,
    route: {
      ...route,
      kind: String(route.kind ?? 'unknown'),
      ...(typeof route.id === 'string' ? { id: route.id } : {}),
    },
    ...(typeof record.status === 'number' ? { status: record.status } : {}),
    ...(typeof record.body === 'string' ? { body: record.body } : {}),
    connectorEvents,
  };
}

export function formatP2PSmokeEvidenceForShare(evidence: P2PSmokeEvidence): string {
  return JSON.stringify(evidence, null, 2);
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return Boolean(value) && typeof value === 'object' && !Array.isArray(value);
}
