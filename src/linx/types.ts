export type LinxLaunchPhase =
  | 'restoring'
  | 'unauthenticated'
  | 'authenticating'
  | 'bootstrapping'
  | 'ready'
  | 'error';

export type LinxMessageRole = 'system' | 'user' | 'assistant';

export type LinxMessageStatus =
  | 'sent'
  | 'streaming'
  | 'completed'
  | 'failed'
  | 'cancelled';

export interface LinxAuthSession {
  issuerUrl: string;
  clientId: string;
  webId: string;
  accessToken: string;
  refreshToken: string;
  accessTokenExpirationDate: string;
  idToken?: string;
}

export interface LinxThreadSummary {
  id: string;
  title: string;
  workspace?: string;
  createdAt: string;
  updatedAt: string;
}

export interface LinxChatMessage {
  id: string;
  threadId: string;
  maker: string;
  role: LinxMessageRole;
  content: string;
  richContent?: string;
  status: LinxMessageStatus;
  createdAt: string;
  updatedAt?: string;
}

export interface RemoteModelSummary {
  id: string;
  provider?: string;
  ownedBy?: string;
  contextWindow?: number;
}

export type RemoteChatContent =
  | string
  | Array<{ type?: string; text?: string; [key: string]: unknown }>
  | null;

export interface RemoteChatMessage {
  role: LinxMessageRole | 'tool';
  content: RemoteChatContent;
  reasoning_content?: string;
  tool_calls?: RemoteChatToolCall[];
  tool_call_id?: string;
  name?: string;
}

export interface RemoteChatToolCall {
  id: string;
  type: 'function';
  function: {
    name: string;
    arguments: string;
  };
}

export interface RemoteChatTool {
  type: 'function';
  function: {
    name: string;
    description?: string;
    parameters?: unknown;
  };
}

export interface RemoteCompletionUsage {
  input: number;
  output: number;
  cacheRead: number;
  cacheWrite: number;
  totalTokens: number;
}

export interface RemoteCompletionResult {
  content: string;
  reasoningContent?: string;
  toolCalls: RemoteChatToolCall[];
  finishReason?: string | null;
  usage?: RemoteCompletionUsage;
}

export interface TokenProvider {
  getAccessToken(forceRefresh?: boolean): Promise<string>;
  expireSession(message?: string): Promise<void>;
}

export interface OIDCDiscoveryDocument {
  issuer: string;
  authorization_endpoint: string;
  token_endpoint: string;
  registration_endpoint?: string;
  revocation_endpoint?: string;
  end_session_endpoint?: string;
}
