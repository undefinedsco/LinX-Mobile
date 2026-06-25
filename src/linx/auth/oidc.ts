import {
  authorize,
  refresh,
  register,
  type AuthConfiguration,
  type ServiceConfiguration,
} from 'react-native-app-auth';
import { LINX_CONTRACT } from '../contract';
import { LinxAppError, LinxAuthExpiredError, isAuthExpiredError } from '../errors';
import type { LinxAuthSession, OIDCDiscoveryDocument, TokenProvider } from '../types';
import { ensureTrailingSlash, trimTrailingSlash } from '../utils';
import { extractWebIdFromIdToken } from './jwt';
import { clearAuthSession, loadAuthSession, saveAuthSession } from './sessionStore';

export async function discoverOIDC(
  issuerUrl: string = LINX_CONTRACT.issuerOrigin,
): Promise<OIDCDiscoveryDocument> {
  const response = await fetch(
    `${trimTrailingSlash(issuerUrl)}/.well-known/openid-configuration`,
    { headers: { Accept: 'application/json' } },
  );

  if (!response.ok) {
    throw new LinxAppError(`OIDC discovery failed (${response.status}).`);
  }

  const json = (await response.json()) as OIDCDiscoveryDocument;
  if (!json.authorization_endpoint || !json.token_endpoint) {
    throw new LinxAppError('OIDC discovery returned an incomplete document.');
  }

  return json;
}

function toServiceConfiguration(
  discovery: OIDCDiscoveryDocument,
): ServiceConfiguration {
  return {
    authorizationEndpoint: discovery.authorization_endpoint,
    tokenEndpoint: discovery.token_endpoint,
    registrationEndpoint: discovery.registration_endpoint,
    revocationEndpoint: discovery.revocation_endpoint,
    endSessionEndpoint: discovery.end_session_endpoint,
  };
}

function makeAuthConfiguration(input: {
  issuerUrl: string;
  clientId: string;
  redirectUrl: string;
  serviceConfiguration: ServiceConfiguration;
}): AuthConfiguration {
  return {
    issuer: trimTrailingSlash(input.issuerUrl),
    serviceConfiguration: input.serviceConfiguration,
    clientId: input.clientId,
    redirectUrl: input.redirectUrl,
    scopes: [...LINX_CONTRACT.loginScopes],
    usePKCE: true,
  };
}

function shouldRefresh(session: LinxAuthSession, forceRefresh: boolean): boolean {
  if (forceRefresh || !session.accessToken) {
    return true;
  }

  const expiresAt = new Date(session.accessTokenExpirationDate).getTime();
  return (
    !Number.isFinite(expiresAt) ||
    expiresAt <= Date.now() + LINX_CONTRACT.tokenRefreshLeewayMs
  );
}

export class LinxAuthController implements TokenProvider {
  private readonly issuerOrigin: string;
  private readonly redirectUrl: string;
  private session: LinxAuthSession | null = null;
  private refreshPromise: Promise<string> | null = null;

  constructor(options: {
    issuerOrigin?: string;
    redirectUrl?: string;
  } = {}) {
    this.issuerOrigin = ensureTrailingSlash(options.issuerOrigin ?? LINX_CONTRACT.issuerOrigin);
    this.redirectUrl = options.redirectUrl ?? LINX_CONTRACT.redirectUrl;
  }

  async restore(): Promise<LinxAuthSession | null> {
    this.session = await loadAuthSession();
    if (!this.session) {
      return null;
    }

    try {
      await this.getAccessToken(false);
      return this.session;
    } catch (error) {
      if (isAuthExpiredError(error)) {
        await this.expireSession();
        return null;
      }
      throw error;
    }
  }

  async login(options: { storageServerUrl?: string } = {}): Promise<LinxAuthSession> {
    const issuerUrl = this.issuerOrigin;
    const discovery = await discoverOIDC(issuerUrl);
    if (!discovery.registration_endpoint) {
      throw new LinxAppError('OIDC provider does not support dynamic client registration.');
    }

    const serviceConfiguration = toServiceConfiguration(discovery);
    const registration = await register({
      issuer: trimTrailingSlash(issuerUrl),
      serviceConfiguration,
      redirectUrls: [this.redirectUrl],
      responseTypes: ['code'],
      grantTypes: ['authorization_code', 'refresh_token'],
      tokenEndpointAuthMethod: 'none',
      additionalParameters: {
        client_name: LINX_CONTRACT.appName,
        scope: LINX_CONTRACT.loginScopes.join(' '),
      },
    });

    const authResult = await authorize({
      ...makeAuthConfiguration({
        issuerUrl,
        clientId: registration.clientId,
        redirectUrl: this.redirectUrl,
        serviceConfiguration,
      }),
      additionalParameters: {
        prompt: 'consent',
      },
    });

    if (!authResult.refreshToken) {
      throw new LinxAppError('OIDC login completed without a refresh token.');
    }

    const session: LinxAuthSession = {
      issuerUrl,
      clientId: registration.clientId,
      webId: extractWebIdFromIdToken(authResult.idToken),
      accessToken: authResult.accessToken,
      refreshToken: authResult.refreshToken,
      accessTokenExpirationDate: authResult.accessTokenExpirationDate,
      idToken: authResult.idToken,
      ...(options.storageServerUrl ? { storageServerUrl: options.storageServerUrl } : {}),
    };
    this.session = session;
    await saveAuthSession(session);
    return session;
  }

  async getSession(): Promise<LinxAuthSession | null> {
    if (!this.session) {
      this.session = await loadAuthSession();
    }
    return this.session;
  }

  async getAccessToken(forceRefresh = false): Promise<string> {
    if (!this.session) {
      this.session = await loadAuthSession();
    }
    if (!this.session) {
      throw new LinxAuthExpiredError('Authentication is required.');
    }

    if (!shouldRefresh(this.session, forceRefresh)) {
      return this.session.accessToken;
    }

    if (!this.refreshPromise) {
      this.refreshPromise = this.refreshAccessToken().finally(() => {
        this.refreshPromise = null;
      });
    }

    return this.refreshPromise;
  }

  async expireSession(): Promise<void> {
    this.session = null;
    await clearAuthSession();
  }

  async logout(): Promise<void> {
    await this.expireSession();
  }

  private async refreshAccessToken(): Promise<string> {
    if (!this.session) {
      throw new LinxAuthExpiredError('Authentication is required.');
    }

    const current = this.session;
    try {
      const discovery = await discoverOIDC(current.issuerUrl);
      const refreshResult = await refresh(
        makeAuthConfiguration({
          issuerUrl: current.issuerUrl,
          clientId: current.clientId,
          redirectUrl: this.redirectUrl,
          serviceConfiguration: toServiceConfiguration(discovery),
        }),
        { refreshToken: current.refreshToken },
      );

      const nextSession: LinxAuthSession = {
        ...current,
        accessToken: refreshResult.accessToken,
        refreshToken: refreshResult.refreshToken ?? current.refreshToken,
        accessTokenExpirationDate: refreshResult.accessTokenExpirationDate,
        idToken: refreshResult.idToken || current.idToken,
      };
      this.session = nextSession;
      await saveAuthSession(nextSession);
      return nextSession.accessToken;
    } catch (error) {
      if (isAuthExpiredError(error)) {
        await this.expireSession();
        throw new LinxAuthExpiredError();
      }
      throw error;
    }
  }
}
