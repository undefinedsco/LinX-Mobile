import { LINX_CONTRACT } from '../contract';
import { ensureTrailingSlash, trimTrailingSlash } from '../utils';

export function resolvePodBaseUrl(input: string | {
  webId: string;
  storageServerUrl?: string;
}): string {
  const webId = typeof input === 'string' ? input : input.webId;
  const target = new URL(webId);
  const parts = target.pathname.split('/').filter(Boolean);
  const profileIndex = parts.indexOf('profile');
  const podParts = profileIndex >= 0 ? parts.slice(0, profileIndex) : parts.slice(0, 1);
  const path = podParts.length > 0 ? `/${podParts.join('/')}/` : '/';

  if (typeof input !== 'string' && input.storageServerUrl) {
    return `${ensureTrailingSlash(input.storageServerUrl)}${path.replace(/^\/+/, '')}`;
  }

  return `${target.origin}${path}`;
}

export function dataContainer(baseUrl: string): string {
  return `${ensureTrailingSlash(baseUrl)}.data/`;
}

export function chatRootContainer(baseUrl: string): string {
  return `${dataContainer(baseUrl)}chat/`;
}

export function chatContainer(
  baseUrl: string,
  chatId = LINX_CONTRACT.defaultChatId,
): string {
  return `${chatRootContainer(baseUrl)}${encodeURIComponent(chatId)}/`;
}

export function chatIndexResource(
  baseUrl: string,
  chatId = LINX_CONTRACT.defaultChatId,
): string {
  return `${chatContainer(baseUrl, chatId)}index.ttl`;
}

export function chatUri(
  baseUrl: string,
  chatId = LINX_CONTRACT.defaultChatId,
): string {
  return `${chatIndexResource(baseUrl, chatId)}#this`;
}

export function threadUri(
  baseUrl: string,
  threadId: string,
  chatId = LINX_CONTRACT.defaultChatId,
): string {
  return `${chatIndexResource(baseUrl, chatId)}#${encodeURIComponent(threadId)}`;
}

export function agentsContainer(baseUrl: string): string {
  return `${dataContainer(baseUrl)}agents/`;
}

export function agentResource(
  baseUrl: string,
  agentId = LINX_CONTRACT.defaultAgentId,
): string {
  return `${agentsContainer(baseUrl)}${encodeURIComponent(agentId)}.ttl`;
}

export function agentUri(
  baseUrl: string,
  agentId = LINX_CONTRACT.defaultAgentId,
): string {
  return agentResource(baseUrl, agentId);
}

export function messageContainers(
  baseUrl: string,
  date: Date,
  chatId = LINX_CONTRACT.defaultChatId,
): string[] {
  const year = String(date.getUTCFullYear());
  const month = String(date.getUTCMonth() + 1).padStart(2, '0');
  const day = String(date.getUTCDate()).padStart(2, '0');
  const yearUrl = `${chatContainer(baseUrl, chatId)}${year}/`;
  const monthUrl = `${yearUrl}${month}/`;
  const dayUrl = `${monthUrl}${day}/`;
  return [yearUrl, monthUrl, dayUrl];
}

export function messageResource(
  baseUrl: string,
  date: Date,
  chatId = LINX_CONTRACT.defaultChatId,
): string {
  const containers = messageContainers(baseUrl, date, chatId);
  return `${containers[containers.length - 1]}messages.ttl`;
}

export function messageUri(
  baseUrl: string,
  messageId: string,
  date: Date,
  chatId = LINX_CONTRACT.defaultChatId,
): string {
  return `${messageResource(baseUrl, date, chatId)}#${encodeURIComponent(messageId)}`;
}

export function chatSparqlEndpoints(
  baseUrl: string,
  chatId = LINX_CONTRACT.defaultChatId,
): string[] {
  return [
    `${chatRootContainer(baseUrl)}-/sparql`,
    `${chatContainer(baseUrl, chatId)}-/sparql`,
  ];
}

export function fragmentId(uri: string): string {
  const hashIndex = uri.lastIndexOf('#');
  if (hashIndex >= 0 && hashIndex < uri.length - 1) {
    return decodeURIComponent(uri.slice(hashIndex + 1));
  }
  const trimmed = trimTrailingSlash(uri);
  return decodeURIComponent(trimmed.slice(trimmed.lastIndexOf('/') + 1));
}
