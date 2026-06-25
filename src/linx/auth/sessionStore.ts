import * as Keychain from 'react-native-keychain';
import { LINX_KEYCHAIN_SERVICE } from '../contract';
import type { LinxAuthSession } from '../types';

const KEYCHAIN_USERNAME = 'linx-mobile';

export async function saveAuthSession(session: LinxAuthSession): Promise<void> {
  await Keychain.setGenericPassword(KEYCHAIN_USERNAME, JSON.stringify(session), {
    service: LINX_KEYCHAIN_SERVICE,
  });
}

export async function loadAuthSession(): Promise<LinxAuthSession | null> {
  const stored = await Keychain.getGenericPassword({
    service: LINX_KEYCHAIN_SERVICE,
  });

  if (!stored) {
    return null;
  }

  try {
    const parsed = JSON.parse(stored.password) as Partial<LinxAuthSession>;
    if (
      typeof parsed.issuerUrl !== 'string' ||
      typeof parsed.clientId !== 'string' ||
      typeof parsed.webId !== 'string' ||
      typeof parsed.accessToken !== 'string' ||
      typeof parsed.refreshToken !== 'string' ||
      typeof parsed.accessTokenExpirationDate !== 'string'
    ) {
      return null;
    }
    return {
      ...(parsed as LinxAuthSession),
      ...(typeof parsed.storageServerUrl === 'string'
        ? { storageServerUrl: parsed.storageServerUrl }
        : {}),
    };
  } catch {
    return null;
  }
}

export async function clearAuthSession(): Promise<void> {
  await Keychain.resetGenericPassword({
    service: LINX_KEYCHAIN_SERVICE,
  });
}
