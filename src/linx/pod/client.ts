import { LINX_CONTRACT } from '../contract';
import { LinxAppError, LinxHTTPError } from '../errors';
import type { TokenProvider } from '../types';
import { withTimeoutSignal } from '../utils';

export interface SPARQLValue {
  type?: string;
  value: string;
  datatype?: string;
}

export interface SPARQLQueryResponse {
  results: {
    bindings: Array<Record<string, SPARQLValue>>;
  };
}

export class PodClient {
  constructor(private readonly tokenProvider: TokenProvider) {}

  async head(url: string): Promise<boolean> {
    const response = await this.authorizedFetch(url, {
      method: 'HEAD',
    });

    if (response.ok) {
      return true;
    }
    if (response.status === 404) {
      return false;
    }

    const detail = await response.text().catch(() => response.statusText);
    throw new LinxHTTPError(
      `Pod HEAD request failed (${response.status}): ${detail}`,
      response.status,
      detail,
    );
  }

  async putContainer(url: string): Promise<void> {
    await this.expectSuccess(
      url,
      {
        method: 'PUT',
        headers: {
          'Content-Type': 'text/turtle',
          Link: '<http://www.w3.org/ns/ldp#BasicContainer>; rel="type"',
        },
        body: '<> a <http://www.w3.org/ns/ldp#BasicContainer> .',
      },
      'Pod container PUT',
    );
  }

  async putResource(url: string, turtle: string): Promise<void> {
    await this.expectSuccess(
      url,
      {
        method: 'PUT',
        headers: {
          'Content-Type': 'text/turtle',
        },
        body: turtle,
      },
      'Pod resource PUT',
    );
  }

  async patch(url: string, sparql: string): Promise<void> {
    await this.expectSuccess(
      url,
      {
        method: 'PATCH',
        headers: {
          'Content-Type': 'application/sparql-update',
        },
        body: sparql,
      },
      'Pod PATCH',
    );
  }

  async query(endpoint: string, sparql: string): Promise<SPARQLQueryResponse> {
    const data = await this.expectSuccess(
      endpoint,
      {
        method: 'POST',
        headers: {
          'Content-Type': 'application/sparql-query',
          Accept: 'application/sparql-results+json',
        },
        body: sparql,
      },
      'Pod SPARQL query',
    );

    try {
      return JSON.parse(data) as SPARQLQueryResponse;
    } catch {
      throw new LinxAppError('Pod SPARQL response was not valid JSON.');
    }
  }

  private async expectSuccess(
    url: string,
    init: RequestInit,
    label: string,
  ): Promise<string> {
    const response = await this.authorizedFetch(url, init);
    const text = await response.text().catch(() => '');
    if (response.ok) {
      return text;
    }

    throw new LinxHTTPError(
      `${label} failed (${response.status}): ${text || response.statusText}`,
      response.status,
      text || response.statusText,
    );
  }

  private async authorizedFetch(
    url: string,
    init: RequestInit,
    retried = false,
  ): Promise<Response> {
    const timeout = withTimeoutSignal(LINX_CONTRACT.podRequestTimeoutMs, init.signal);
    try {
      const token = await this.tokenProvider.getAccessToken(retried);
      const response = await fetch(url, {
        ...init,
        signal: timeout.signal,
        headers: {
          ...init.headers,
          Authorization: `Bearer ${token}`,
        },
      });

      if (response.status === 401 && !retried) {
        return this.authorizedFetch(url, init, true);
      }
      if (response.status === 401) {
        await this.tokenProvider.expireSession();
      }
      return response;
    } finally {
      timeout.cleanup();
    }
  }
}
