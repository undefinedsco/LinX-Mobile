import { LINX_CONTRACT } from '../contract';
import { LinxHTTPError } from '../errors';
import type {
  RemoteChatMessage,
  RemoteChatTool,
  RemoteChatToolCall,
  RemoteCompletionResult,
  RemoteCompletionUsage,
  RemoteModelSummary,
  TokenProvider,
} from '../types';
import { isAbortError, withTimeoutSignal } from '../utils';
import { resolveRuntimeApiBaseUrlForIssuerUrl } from './runtimeTarget';

interface RemoteCompletionRawUsage {
  prompt_tokens?: number;
  completion_tokens?: number;
  total_tokens?: number;
  prompt_tokens_details?: {
    cached_tokens?: number;
    cache_write_tokens?: number;
  };
  completion_tokens_details?: {
    reasoning_tokens?: number;
  };
}

function nonNegative(value: unknown): number {
  return typeof value === 'number' && Number.isFinite(value) && value > 0
    ? value
    : 0;
}

function normalizeUsage(raw?: RemoteCompletionRawUsage): RemoteCompletionUsage | undefined {
  if (!raw) {
    return undefined;
  }

  const promptTokens = nonNegative(raw.prompt_tokens);
  const reportedCachedTokens = nonNegative(raw.prompt_tokens_details?.cached_tokens);
  const cacheWrite = nonNegative(raw.prompt_tokens_details?.cache_write_tokens);
  const cacheRead =
    cacheWrite > 0
      ? Math.max(0, reportedCachedTokens - cacheWrite)
      : reportedCachedTokens;
  const input = Math.max(0, promptTokens - cacheRead - cacheWrite);
  const output =
    nonNegative(raw.completion_tokens) +
    nonNegative(raw.completion_tokens_details?.reasoning_tokens);
  const computedTotal = input + output + cacheRead + cacheWrite;

  return {
    input,
    output,
    cacheRead,
    cacheWrite,
    totalTokens: computedTotal > 0 ? computedTotal : nonNegative(raw.total_tokens),
  };
}

function normalizeRemoteContent(
  content:
    | string
    | Array<{ type?: string; text?: string; [key: string]: unknown }>
    | null
    | undefined,
): string {
  if (typeof content === 'string') {
    return content;
  }
  if (Array.isArray(content)) {
    return content
      .map(part => (typeof part.text === 'string' ? part.text : ''))
      .join('');
  }
  return '';
}

function normalizeReasoning(message: {
  reasoning_content?: string | null;
  reasoning?: string | null;
  reasoning_text?: string | null;
} | null | undefined): string | undefined {
  const value =
    message?.reasoning_content ?? message?.reasoning ?? message?.reasoning_text;
  const trimmed = typeof value === 'string' ? value.trim() : '';
  return trimmed ? trimmed : undefined;
}

async function fetchWithAuthRetry(
  tokenProvider: TokenProvider,
  input: RequestInfo,
  init: RequestInit,
): Promise<Response> {
  let token = await tokenProvider.getAccessToken(false);
  let response = await fetch(input, {
    ...init,
    headers: {
      ...init.headers,
      Authorization: `Bearer ${token}`,
    },
  });

  if (response.status !== 401) {
    return response;
  }

  token = await tokenProvider.getAccessToken(true);
  response = await fetch(input, {
    ...init,
    headers: {
      ...init.headers,
      Authorization: `Bearer ${token}`,
    },
  });

  if (response.status === 401) {
    await tokenProvider.expireSession();
  }
  return response;
}

export async function listRemoteModels(options: {
  issuerUrl: string;
  tokenProvider: TokenProvider;
  timeoutMs?: number;
}): Promise<RemoteModelSummary[]> {
  const baseUrl = resolveRuntimeApiBaseUrlForIssuerUrl(options.issuerUrl);
  const timeout = withTimeoutSignal(options.timeoutMs ?? 10_000);
  try {
    const response = await fetchWithAuthRetry(
      options.tokenProvider,
      `${baseUrl}/models`,
      {
        signal: timeout.signal,
        headers: {
          Accept: 'application/json',
        },
      },
    );

    if (!response.ok) {
      const text = await response.text().catch(() => response.statusText);
      throw new LinxHTTPError(
        `Models request failed (${response.status}): ${text}`,
        response.status,
        text,
      );
    }

    const json = (await response.json()) as {
      data?: Array<{
        id: string;
        provider?: string;
        owned_by?: string;
        context_window?: number;
      }>;
    };

    return Array.isArray(json.data)
      ? json.data.map(model => ({
          id: model.id,
          provider: normalizeModelProvider(model.id, model.provider),
          ownedBy: normalizeModelProvider(model.id, model.owned_by),
          contextWindow: model.context_window,
        }))
      : [];
  } finally {
    timeout.cleanup();
  }
}

export function pickPreferredModelId(models: Array<{ id: string }>): string {
  const ids = models
    .map(model => model.id)
    .filter(id => typeof id === 'string' && id.trim().length > 0);
  return (
    ids.find(id => id === LINX_CONTRACT.defaultModelId) ??
    ids[0] ??
    LINX_CONTRACT.defaultModelId
  );
}

export function makeRemoteCompletionRequestBody(options: {
  model?: string;
  messages: RemoteChatMessage[];
  tools?: RemoteChatTool[];
}): {
  model: string;
  stream: false;
  messages: RemoteChatMessage[];
  tools?: RemoteChatTool[];
  tool_choice?: 'auto';
} {
  const body: {
    model: string;
    stream: false;
    messages: RemoteChatMessage[];
    tools?: RemoteChatTool[];
    tool_choice?: 'auto';
  } = {
    model: options.model || LINX_CONTRACT.defaultModelId,
    stream: false,
    messages: options.messages,
  };

  if (options.tools && options.tools.length > 0) {
    body.tools = options.tools;
    body.tool_choice = 'auto';
  }

  return body;
}

export async function createRemoteCompletion(options: {
  issuerUrl: string;
  tokenProvider: TokenProvider;
  model?: string;
  messages: RemoteChatMessage[];
  tools?: RemoteChatTool[];
  signal?: AbortSignal;
}): Promise<RemoteCompletionResult> {
  const baseUrl = resolveRuntimeApiBaseUrlForIssuerUrl(options.issuerUrl);
  const timeout = withTimeoutSignal(
    LINX_CONTRACT.runtimeRequestTimeoutMs,
    options.signal,
  );
  try {
    const response = await fetchWithAuthRetry(
      options.tokenProvider,
      `${baseUrl}/chat/completions`,
      {
        method: 'POST',
        signal: timeout.signal,
        headers: {
          'Content-Type': 'application/json',
          Accept: 'application/json',
        },
        body: JSON.stringify(
          makeRemoteCompletionRequestBody({
            model: options.model,
            messages: options.messages,
            tools: options.tools,
          }),
        ),
      },
    );

    if (!response.ok) {
      const text = await response.text().catch(() => response.statusText);
      throw new LinxHTTPError(
        `Chat request failed (${response.status}): ${text}`,
        response.status,
        text,
      );
    }

    return decodeRemoteCompletionResult(await response.json());
  } catch (error) {
    if (isAbortError(error) && options.signal?.aborted) {
      throw new LinxAppAbortError('LinX Cloud request aborted by user.');
    }
    throw error;
  } finally {
    timeout.cleanup();
  }
}

export class LinxAppAbortError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'LinxAppAbortError';
  }
}

export function decodeRemoteCompletionResult(raw: unknown): RemoteCompletionResult {
  const json = raw as {
    usage?: RemoteCompletionRawUsage;
    choices?: Array<{
      finish_reason?: string | null;
      usage?: RemoteCompletionRawUsage;
      message?: {
        content?:
          | string
          | Array<{ type?: string; text?: string; [key: string]: unknown }>
          | null;
        reasoning_content?: string | null;
        reasoning?: string | null;
        reasoning_text?: string | null;
        tool_calls?: RemoteChatToolCall[];
      };
    }>;
  };

  const choice = json.choices?.[0];
  const message = choice?.message;
  const content = normalizeRemoteContent(message?.content);
  const reasoningContent = normalizeReasoning(message);
  const toolCalls = Array.isArray(message?.tool_calls) ? message.tool_calls : [];
  const usage = normalizeUsage(json.usage ?? choice?.usage);

  if (content || reasoningContent || toolCalls.length > 0) {
    return {
      content,
      reasoningContent,
      toolCalls,
      finishReason: choice?.finish_reason,
      usage,
    };
  }

  throw new Error('Empty response from remote model');
}

function normalizeModelProvider(
  modelId: string,
  provider: string | undefined,
): string | undefined {
  return LINX_CONTRACT.fallbackModelIds.includes(
    modelId as (typeof LINX_CONTRACT.fallbackModelIds)[number],
  )
    ? 'undefineds'
    : provider;
}
