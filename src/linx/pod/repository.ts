import { LINX_CONTRACT } from '../contract';
import type {
  LinxAuthSession,
  LinxChatMessage,
  LinxMessageRole,
  LinxThreadSummary,
} from '../types';
import { makeUUID } from '../utils';
import type { PodClient, SPARQLQueryResponse, SPARQLValue } from './client';
import {
  agentResource,
  agentUri,
  agentsContainer,
  chatContainer,
  chatIndexResource,
  chatRootContainer,
  chatSparqlEndpoints,
  chatUri,
  dataContainer,
  fragmentId,
  messageContainers,
  messageResource,
  messageUri,
  resolvePodBaseUrl,
  threadUri,
} from './paths';
import {
  agentResourceTurtle,
  chatResourceTurtle,
  createThreadPatch,
  emptyTurtleResource,
  insertMessagePatch,
  messagesQuery,
  patchActivity,
  threadsQuery,
} from './sparql';

function parseDate(value?: string): string | null {
  if (!value) {
    return null;
  }
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? null : date.toISOString();
}

function bindingValue(binding: Record<string, SPARQLValue>, key: string): string | undefined {
  const value = binding[key]?.value;
  return typeof value === 'string' && value.length > 0 ? value : undefined;
}

function mapThreadBinding(binding: Record<string, SPARQLValue>): LinxThreadSummary | null {
  const thread = bindingValue(binding, 'thread');
  const createdAt = parseDate(bindingValue(binding, 'createdAt'));
  const updatedAt =
    parseDate(bindingValue(binding, 'updatedAt')) ?? createdAt ?? undefined;

  if (!thread || !createdAt || !updatedAt) {
    return null;
  }

  return {
    id: fragmentId(thread),
    title: bindingValue(binding, 'title') ?? LINX_CONTRACT.defaultThreadTitle,
    workspace: bindingValue(binding, 'workspace'),
    createdAt,
    updatedAt,
  };
}

function mapMessageBinding(
  binding: Record<string, SPARQLValue>,
  threadId: string,
): LinxChatMessage | null {
  const message = bindingValue(binding, 'message');
  const maker = bindingValue(binding, 'maker');
  const role = bindingValue(binding, 'role') as LinxMessageRole | undefined;
  const content = bindingValue(binding, 'content');
  const createdAt = parseDate(bindingValue(binding, 'createdAt'));

  if (
    !message ||
    !maker ||
    !role ||
    !content ||
    !createdAt ||
    !['system', 'user', 'assistant'].includes(role)
  ) {
    return null;
  }

  return {
    id: fragmentId(message),
    threadId,
    maker,
    role,
    content,
    richContent: bindingValue(binding, 'richContent'),
    status:
      (bindingValue(binding, 'status') as LinxChatMessage['status'] | undefined) ??
      'sent',
    createdAt,
    updatedAt: parseDate(bindingValue(binding, 'updatedAt')) ?? undefined,
  };
}

export class PodChatRepository {
  constructor(private readonly client: PodClient) {}

  async bootstrap(session: LinxAuthSession, modelId: string): Promise<void> {
    const baseUrl = this.baseUrl(session);
    const now = new Date();

    await this.ensureContainer(dataContainer(baseUrl));
    await this.ensureContainer(chatRootContainer(baseUrl));
    await this.ensureContainer(chatContainer(baseUrl));
    await this.ensureContainer(agentsContainer(baseUrl));

    const chatResource = chatIndexResource(baseUrl);
    if (!(await this.client.head(chatResource))) {
      await this.client.putResource(
        chatResource,
        chatResourceTurtle({
          chatUri: chatUri(baseUrl),
          createdAt: now,
        }),
      );
    }

    const agent = agentResource(baseUrl);
    if (!(await this.client.head(agent))) {
      await this.client.putResource(
        agent,
        agentResourceTurtle({
          agentUri: agentUri(baseUrl),
          modelId,
          createdAt: now,
        }),
      );
    }
  }

  async listThreads(session: LinxAuthSession, limit = LINX_CONTRACT.pageSize): Promise<LinxThreadSummary[]> {
    const baseUrl = this.baseUrl(session);
    const sparql = threadsQuery({
      chatUri: chatUri(baseUrl),
      limit,
    });
    const response = await this.queryFirstUsefulEndpoint(baseUrl, sparql, bindings =>
      bindings.map(mapThreadBinding).filter((thread): thread is LinxThreadSummary => Boolean(thread)),
    );

    return response.sort((left, right) =>
      right.updatedAt.localeCompare(left.updatedAt),
    );
  }

  async createThread(
    session: LinxAuthSession,
    title = LINX_CONTRACT.defaultThreadTitle,
    workspace = LINX_CONTRACT.defaultThreadWorkspace,
  ): Promise<LinxThreadSummary> {
    const baseUrl = this.baseUrl(session);
    const id = makeUUID();
    const now = new Date();
    const nowIso = now.toISOString();

    await this.client.patch(
      chatIndexResource(baseUrl),
      createThreadPatch({
        chatUri: chatUri(baseUrl),
        threadUri: threadUri(baseUrl, id),
        title,
        workspace,
        createdAt: now,
      }),
    );

    return {
      id,
      title,
      workspace,
      createdAt: nowIso,
      updatedAt: nowIso,
    };
  }

  async loadMessages(
    session: LinxAuthSession,
    threadId: string,
    limit?: number,
    offset = 0,
  ): Promise<LinxChatMessage[]> {
    const baseUrl = this.baseUrl(session);
    const response = await this.queryFirstUsefulEndpoint(
      baseUrl,
      messagesQuery({
        threadUri: threadUri(baseUrl, threadId),
        limit,
        offset,
      }),
      bindings =>
        bindings
          .map(binding => mapMessageBinding(binding, threadId))
          .filter((message): message is LinxChatMessage => Boolean(message)),
    );

    return response.sort((left, right) =>
      left.createdAt.localeCompare(right.createdAt),
    );
  }

  async appendUserMessage(
    session: LinxAuthSession,
    threadId: string,
    content: string,
  ): Promise<LinxChatMessage> {
    return this.appendMessage(session, threadId, session.webId, 'user', content);
  }

  async appendAssistantMessage(
    session: LinxAuthSession,
    threadId: string,
    content: string,
  ): Promise<LinxChatMessage> {
    const baseUrl = this.baseUrl(session);
    return this.appendMessage(
      session,
      threadId,
      agentUri(baseUrl),
      'assistant',
      content,
    );
  }

  private async appendMessage(
    session: LinxAuthSession,
    threadId: string,
    maker: string,
    role: LinxMessageRole,
    content: string,
  ): Promise<LinxChatMessage> {
    const baseUrl = this.baseUrl(session);
    const now = new Date();
    const id = makeUUID();

    await this.ensureMessageDocument(baseUrl, now);
    await this.client.patch(
      messageResource(baseUrl, now),
      insertMessagePatch({
        chatUri: chatUri(baseUrl),
        threadUri: threadUri(baseUrl, threadId),
        messageUri: messageUri(baseUrl, id, now),
        makerUri: maker,
        role,
        content,
        status: 'sent',
        createdAt: now,
      }),
    );
    await this.client.patch(
      chatIndexResource(baseUrl),
      patchActivity({
        chatUri: chatUri(baseUrl),
        threadUri: threadUri(baseUrl, threadId),
        preview: content.slice(0, 100),
        updatedAt: now,
      }),
    );

    return {
      id,
      threadId,
      maker,
      role,
      content,
      status: 'sent',
      createdAt: now.toISOString(),
      updatedAt: now.toISOString(),
    };
  }

  private async ensureMessageDocument(baseUrl: string, date: Date): Promise<void> {
    for (const container of messageContainers(baseUrl, date)) {
      await this.ensureContainer(container);
    }

    const resource = messageResource(baseUrl, date);
    if (!(await this.client.head(resource))) {
      await this.client.putResource(resource, emptyTurtleResource());
    }
  }

  private async ensureContainer(url: string): Promise<void> {
    if (!(await this.client.head(url))) {
      await this.client.putContainer(url);
    }
  }

  private async queryFirstUsefulEndpoint<T>(
    baseUrl: string,
    sparql: string,
    mapBindings: (bindings: SPARQLQueryResponse['results']['bindings']) => T[],
  ): Promise<T[]> {
    let firstEmpty: T[] | null = null;
    let lastError: Error | null = null;

    for (const endpoint of chatSparqlEndpoints(baseUrl)) {
      try {
        const response = await this.client.query(endpoint, sparql);
        const mapped = mapBindings(response.results.bindings ?? []);
        if (mapped.length > 0) {
          return mapped;
        }
        firstEmpty = firstEmpty ?? mapped;
      } catch (error) {
        lastError = error instanceof Error ? error : new Error(String(error));
      }
    }

    if (firstEmpty) {
      return firstEmpty;
    }
    throw lastError ?? new Error('Pod query failed.');
  }

  private baseUrl(session: LinxAuthSession): string {
    return resolvePodBaseUrl({
      webId: session.webId,
      storageServerUrl: session.storageServerUrl,
    });
  }
}
