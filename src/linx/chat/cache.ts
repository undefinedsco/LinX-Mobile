import AsyncStorage from '@react-native-async-storage/async-storage';
import { LINX_CONTRACT, LINX_STORAGE_KEYS } from '../contract';
import type { LinxChatMessage, LinxThreadSummary } from '../types';

const CHAT_CACHE_SCHEMA_VERSION = 1;

interface CachedThreadsEnvelope {
  schemaVersion: number;
  cachedAt: string;
  webId: string;
  threads: LinxThreadSummary[];
}

interface CachedMessagesEnvelope {
  schemaVersion: number;
  cachedAt: string;
  webId: string;
  threadId: string;
  messages: LinxChatMessage[];
}

export interface LinxChatLaunchSnapshot {
  threads: LinxThreadSummary[];
  selectedThread: LinxThreadSummary | null;
  messages: LinxChatMessage[];
}

function keyForRecentThread(webId: string): string {
  return `${LINX_STORAGE_KEYS.recentThreadId}:${webId}`;
}

function keyForThreadsSnapshot(webId: string): string {
  return `${LINX_STORAGE_KEYS.threadsSnapshot}:${webId}`;
}

function keyForMessagesSnapshot(webId: string, threadId: string): string {
  return `${LINX_STORAGE_KEYS.messagesSnapshot}:${webId}:${threadId}`;
}

function isString(value: unknown): value is string {
  return typeof value === 'string' && value.length > 0;
}

function isThreadSummary(value: unknown): value is LinxThreadSummary {
  const candidate = value as Partial<LinxThreadSummary>;
  return (
    typeof value === 'object' &&
    value !== null &&
    isString(candidate.id) &&
    isString(candidate.title) &&
    isString(candidate.createdAt) &&
    isString(candidate.updatedAt) &&
    (candidate.workspace === undefined || typeof candidate.workspace === 'string')
  );
}

function isChatMessage(value: unknown): value is LinxChatMessage {
  const candidate = value as Partial<LinxChatMessage>;
  return (
    typeof value === 'object' &&
    value !== null &&
    isString(candidate.id) &&
    isString(candidate.threadId) &&
    isString(candidate.maker) &&
    ['system', 'user', 'assistant'].includes(String(candidate.role)) &&
    typeof candidate.content === 'string' &&
    ['sent', 'streaming', 'completed', 'failed', 'cancelled'].includes(
      String(candidate.status),
    ) &&
    isString(candidate.createdAt) &&
    (candidate.richContent === undefined || typeof candidate.richContent === 'string') &&
    (candidate.updatedAt === undefined || typeof candidate.updatedAt === 'string')
  );
}

function sortThreads(threads: LinxThreadSummary[]): LinxThreadSummary[] {
  return [...threads].sort((left, right) =>
    right.updatedAt.localeCompare(left.updatedAt),
  );
}

function sortMessages(messages: LinxChatMessage[]): LinxChatMessage[] {
  return [...messages].sort((left, right) => {
    const dateComparison = left.createdAt.localeCompare(right.createdAt);
    return dateComparison === 0 ? left.id.localeCompare(right.id) : dateComparison;
  });
}

async function parseJSON<T>(key: string): Promise<T | null> {
  try {
    const raw = await AsyncStorage.getItem(key);
    if (!raw) {
      return null;
    }
    return JSON.parse(raw) as T;
  } catch {
    return null;
  }
}

export async function loadRecentThreadId(webId: string): Promise<string | null> {
  try {
    return await AsyncStorage.getItem(keyForRecentThread(webId));
  } catch {
    return null;
  }
}

export async function saveRecentThreadId(
  webId: string,
  threadId: string,
): Promise<void> {
  try {
    await AsyncStorage.setItem(keyForRecentThread(webId), threadId);
  } catch {
    // Cache failures must not block the chat flow.
  }
}

export async function clearRecentThreadId(webId: string): Promise<void> {
  try {
    await AsyncStorage.removeItem(keyForRecentThread(webId));
  } catch {
    // Cache failures must not block the chat flow.
  }
}

export async function loadThreadsSnapshot(
  webId: string,
  limit: number = LINX_CONTRACT.pageSize,
): Promise<LinxThreadSummary[]> {
  const envelope = await parseJSON<Partial<CachedThreadsEnvelope>>(
    keyForThreadsSnapshot(webId),
  );
  if (
    envelope?.schemaVersion !== CHAT_CACHE_SCHEMA_VERSION ||
    envelope.webId !== webId ||
    !Array.isArray(envelope.threads)
  ) {
    return [];
  }

  return sortThreads(
    envelope.threads.filter(isThreadSummary),
  ).slice(0, limit);
}

export async function saveThreadsSnapshot(
  webId: string,
  threads: LinxThreadSummary[],
): Promise<void> {
  const envelope: CachedThreadsEnvelope = {
    schemaVersion: CHAT_CACHE_SCHEMA_VERSION,
    cachedAt: new Date().toISOString(),
    webId,
    threads: sortThreads(threads).slice(0, LINX_CONTRACT.pageSize),
  };

  try {
    await AsyncStorage.setItem(keyForThreadsSnapshot(webId), JSON.stringify(envelope));
  } catch {
    // Cache failures must not block the chat flow.
  }
}

export async function loadMessagesSnapshot(
  webId: string,
  threadId: string,
  limit: number = LINX_CONTRACT.pageSize,
): Promise<LinxChatMessage[]> {
  const envelope = await parseJSON<Partial<CachedMessagesEnvelope>>(
    keyForMessagesSnapshot(webId, threadId),
  );
  if (
    envelope?.schemaVersion !== CHAT_CACHE_SCHEMA_VERSION ||
    envelope.webId !== webId ||
    envelope.threadId !== threadId ||
    !Array.isArray(envelope.messages)
  ) {
    return [];
  }

  return sortMessages(
    envelope.messages.filter(isChatMessage),
  ).slice(-limit);
}

export async function saveMessagesSnapshot(
  webId: string,
  threadId: string,
  messages: LinxChatMessage[],
): Promise<void> {
  const envelope: CachedMessagesEnvelope = {
    schemaVersion: CHAT_CACHE_SCHEMA_VERSION,
    cachedAt: new Date().toISOString(),
    webId,
    threadId,
    messages: sortMessages(
      messages.filter(message => message.threadId === threadId),
    ).slice(-LINX_CONTRACT.pageSize),
  };

  try {
    await AsyncStorage.setItem(
      keyForMessagesSnapshot(webId, threadId),
      JSON.stringify(envelope),
    );
  } catch {
    // Cache failures must not block the chat flow.
  }
}

export async function loadLaunchSnapshot(
  webId: string,
  limit: number = LINX_CONTRACT.pageSize,
): Promise<LinxChatLaunchSnapshot | null> {
  const threads = await loadThreadsSnapshot(webId, limit);
  if (threads.length === 0) {
    return null;
  }

  const recentThreadId = await loadRecentThreadId(webId);
  const selectedThread =
    threads.find(thread => thread.id === recentThreadId) ?? threads[0] ?? null;
  const messages = selectedThread
    ? await loadMessagesSnapshot(webId, selectedThread.id, limit)
    : [];

  return {
    threads,
    selectedThread,
    messages,
  };
}

export async function clearUserChatCache(webId: string): Promise<void> {
  try {
    const keys = await AsyncStorage.getAllKeys();
    const prefixes = [
      keyForRecentThread(webId),
      keyForThreadsSnapshot(webId),
      `${LINX_STORAGE_KEYS.messagesSnapshot}:${webId}:`,
    ];
    const keysToRemove = keys.filter(key =>
      prefixes.some(prefix => key === prefix || key.startsWith(prefix)),
    );

    if (keysToRemove.length > 0) {
      await Promise.all(keysToRemove.map(key => AsyncStorage.removeItem(key)));
    }
  } catch {
    // Cache failures must not block logout or auth recovery.
  }
}
