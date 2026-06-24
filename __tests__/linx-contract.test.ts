import { extractWebIdFromIdToken } from '../src/linx/auth/jwt';
import { LINX_CONTRACT } from '../src/linx/contract';
import {
  resolvePodBaseUrl,
  chatIndexResource,
  messageResource,
} from '../src/linx/pod/paths';
import { normalizeCustomStorageServerUrl } from '../src/linx/storageSettings';
import {
  createThreadPatch,
  escapeLiteral,
  insertMessagePatch,
  threadsQuery,
} from '../src/linx/pod/sparql';
import {
  createRemoteCompletion,
  decodeRemoteCompletionResult,
  makeRemoteCompletionRequestBody,
  pickPreferredModelId,
} from '../src/linx/runtime/chatApi';
import {
  resolveRuntimeApiBaseUrl,
  resolveRuntimeApiBaseUrlForIssuerUrl,
} from '../src/linx/runtime/runtimeTarget';

function makeJwt(payload: Record<string, unknown>): string {
  const encoded = base64UrlEncode(JSON.stringify(payload));
  return `header.${encoded}.signature`;
}

function base64UrlEncode(value: string): string {
  const alphabet =
    'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
  let output = '';

  for (let index = 0; index < value.length; index += 3) {
    const byte1 = value.charCodeAt(index);
    const byte2 = value.charCodeAt(index + 1);
    const byte3 = value.charCodeAt(index + 2);
    const hasByte2 = index + 1 < value.length;
    const hasByte3 = index + 2 < value.length;

    output += alphabet[Math.floor(byte1 / 4)];
    output += alphabet[(byte1 % 4) * 16 + (hasByte2 ? Math.floor(byte2 / 16) : 0)];
    output += hasByte2
      ? alphabet[(byte2 % 16) * 4 + (hasByte3 ? Math.floor(byte3 / 64) : 0)]
      : '=';
    output += hasByte3 ? alphabet[byte3 % 64] : '=';
  }

  return output
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(new RegExp('=+$'), '');
}

test('extractWebIdFromIdToken prefers webid and falls back to URL sub', () => {
  expect(
    extractWebIdFromIdToken(
      makeJwt({
        webid: 'https://pod.example/profile/card#me',
        sub: 'https://subject.example/profile/card#me',
      }),
    ),
  ).toBe('https://pod.example/profile/card#me');

  expect(
    extractWebIdFromIdToken(
      makeJwt({
        sub: 'https://subject.example/profile/card#me',
      }),
    ),
  ).toBe('https://subject.example/profile/card#me');
});

test('resolves Pod and runtime URLs using CLI-compatible rules', () => {
  expect(LINX_CONTRACT.pageSize).toBe(20);
  expect(LINX_CONTRACT.defaultChatId).toBe('mobile-default');
  expect(LINX_CONTRACT.defaultAgentId).toBe('linx-mobile-assistant');

  expect(resolvePodBaseUrl('https://alice.example/profile/card#me')).toBe(
    'https://alice.example/',
  );
  expect(resolvePodBaseUrl('https://pods.example/alice/profile/card#me')).toBe(
    'https://pods.example/alice/',
  );
  expect(
    resolvePodBaseUrl({
      webId: 'https://id.undefineds.co/alice/profile/card#me',
      storageServerUrl: 'https://node-0000.undefineds.co',
    }),
  ).toBe('https://node-0000.undefineds.co/alice/');
  expect(
    chatIndexResource('https://pods.example/alice/'),
  ).toBe('https://pods.example/alice/.data/chat/mobile-default/index.ttl');
  expect(
    messageResource(
      'https://pods.example/alice/',
      new Date('1970-01-02T03:04:05Z'),
    ),
  ).toBe(
    'https://pods.example/alice/.data/chat/mobile-default/1970/01/02/messages.ttl',
  );

  expect(resolveRuntimeApiBaseUrlForIssuerUrl('https://id.undefineds.co/')).toBe(
    'https://api.undefineds.co/v1',
  );
  expect(resolveRuntimeApiBaseUrl('https://api.undefineds.co/v1/')).toBe(
    'https://api.undefineds.co/v1',
  );
});

test('custom SP server is a storage override, not an IDP/provider shorthand', () => {
  expect(
    normalizeCustomStorageServerUrl('https://node-0000.undefineds.co'),
  ).toBe('https://node-0000.undefineds.co/');
  expect(normalizeCustomStorageServerUrl('   ')).toBeUndefined();
  expect(() =>
    normalizeCustomStorageServerUrl('alice.node-0000.undefineds.co'),
  ).toThrow('Custom SP server must be an absolute http(s) URL');
  expect(() =>
    normalizeCustomStorageServerUrl('https://node-0000.undefineds.co/alice/'),
  ).toThrow('Custom SP server must not include a pod owner path');
});

test('SPARQL builders escape user values and target mobile chat space', () => {
  expect(escapeLiteral('hello "LinX"\nnext')).toBe('"""hello "LinX"\nnext"""');

  const query = threadsQuery({
    chatUri: 'https://pod.example/.data/chat/mobile-default/index.ttl#this',
    limit: 20,
  });
  expect(query).toContain('SELECT ?thread ?title ?workspace ?createdAt ?updatedAt');
  expect(query).toContain('LIMIT 20');

  const createdAt = new Date('1970-01-01T00:00:00.000Z');
  const threadPatch = createThreadPatch({
    chatUri: 'https://pod.example/.data/chat/mobile-default/index.ttl#this',
    threadUri: 'https://pod.example/.data/chat/mobile-default/index.ttl#thread',
    title: 'Mobile Session',
    workspace: 'co.undefineds.linx.mobile://workspace/default',
    createdAt,
  });
  expect(threadPatch).toContain('udfs:workspace <co.undefineds.linx.mobile://workspace/default>');

  const messagePatch = insertMessagePatch({
    chatUri: 'https://pod.example/.data/chat/mobile-default/index.ttl#this',
    threadUri: 'https://pod.example/.data/chat/mobile-default/index.ttl#thread',
    messageUri: 'https://pod.example/.data/chat/mobile-default/1970/01/01/messages.ttl#m',
    makerUri: 'https://pod.example/profile/card#me',
    role: 'user',
    content: 'hello',
    status: 'sent',
    createdAt,
  });
  expect(messagePatch).toContain('wf:message');
  expect(messagePatch).toContain('udfs:messageType "user"');
});

test('runtime request and response match CLI chat completion contract', () => {
  expect(
    makeRemoteCompletionRequestBody({
      messages: [{ role: 'user', content: 'hello' }],
    }),
  ).toEqual({
    model: 'linx-lite',
    stream: false,
    messages: [{ role: 'user', content: 'hello' }],
  });

  expect(
    makeRemoteCompletionRequestBody({
      messages: [],
      tools: [
        {
          type: 'function',
          function: {
            name: 'search',
            parameters: { type: 'object' },
          },
        },
      ],
    }).tool_choice,
  ).toBe('auto');

  expect(pickPreferredModelId([{ id: 'other' }, { id: 'linx-lite' }])).toBe(
    'linx-lite',
  );

  const result = decodeRemoteCompletionResult({
    usage: {
      prompt_tokens: 10,
      completion_tokens: 5,
      total_tokens: 99,
      prompt_tokens_details: {
        cached_tokens: 4,
        cache_write_tokens: 1,
      },
      completion_tokens_details: {
        reasoning_tokens: 2,
      },
    },
    choices: [
      {
        finish_reason: 'tool_calls',
        message: {
          content: [{ type: 'text', text: 'hello' }],
          reasoning_content: 'thinking',
          tool_calls: [
            {
              id: 'call-1',
              type: 'function',
              function: { name: 'search', arguments: '{"query":"hello"}' },
            },
          ],
        },
      },
    ],
  });

  expect(result.content).toBe('hello');
  expect(result.reasoningContent).toBe('thinking');
  expect(result.toolCalls).toHaveLength(1);
  expect(result.usage).toEqual({
    input: 6,
    output: 7,
    cacheRead: 3,
    cacheWrite: 1,
    totalTokens: 17,
  });
});

test('runtime retries a 401 with a forced token refresh', async () => {
  const first = new Response('unauthorized', { status: 401 });
  const second = new Response(
    JSON.stringify({
      choices: [{ message: { content: 'ok' } }],
    }),
    { status: 200, headers: { 'Content-Type': 'application/json' } },
  );
  const fetchSpy = jest
    .spyOn(globalThis, 'fetch')
    .mockResolvedValueOnce(first)
    .mockResolvedValueOnce(second);
  const tokenProvider = {
    getAccessToken: jest
      .fn()
      .mockResolvedValueOnce('old-token')
      .mockResolvedValueOnce('new-token'),
    expireSession: jest.fn(),
  };

  await expect(
    createRemoteCompletion({
      issuerUrl: 'https://id.undefineds.co/',
      tokenProvider,
      messages: [{ role: 'user', content: 'hello' }],
    }),
  ).resolves.toMatchObject({ content: 'ok' });

  expect(tokenProvider.getAccessToken).toHaveBeenNthCalledWith(1, false);
  expect(tokenProvider.getAccessToken).toHaveBeenNthCalledWith(2, true);
  expect(fetchSpy.mock.calls[1][1]?.headers).toMatchObject({
    Authorization: 'Bearer new-token',
  });

  fetchSpy.mockRestore();
});
