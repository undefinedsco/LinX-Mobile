import AsyncStorage from '@react-native-async-storage/async-storage';
import { LINX_CONTRACT, LINX_STORAGE_KEYS } from '../src/linx/contract';
import type { LinxChatMessage, LinxThreadSummary } from '../src/linx/types';
import {
  clearUserChatCache,
  loadLaunchSnapshot,
  loadMessagesSnapshot,
  loadThreadsSnapshot,
  saveMessagesSnapshot,
  saveRecentThreadId,
  saveThreadsSnapshot,
} from '../src/linx/chat/cache';

jest.mock('@react-native-async-storage/async-storage', () => {
  const store = new Map<string, string>();
  return {
    __store: store,
    getItem: jest.fn(async (key: string) => store.get(key) ?? null),
    setItem: jest.fn(async (key: string, value: string) => {
      store.set(key, value);
    }),
    removeItem: jest.fn(async (key: string) => {
      store.delete(key);
    }),
    getAllKeys: jest.fn(async () => Array.from(store.keys())),
    multiRemove: jest.fn(async (keys: string[]) => {
      keys.forEach(key => store.delete(key));
    }),
  };
});

const storage = AsyncStorage as unknown as {
  __store: Map<string, string>;
};

const webId = 'https://alice.example/profile/card#me';
const otherWebId = 'https://bob.example/profile/card#me';

function makeThread(id: string, updatedAt: string): LinxThreadSummary {
  return {
    id,
    title: `Thread ${id}`,
    createdAt: updatedAt,
    updatedAt,
  };
}

function makeMessage(
  id: string,
  threadId: string,
  createdAt: string,
): LinxChatMessage {
  return {
    id,
    threadId,
    maker: webId,
    role: 'user',
    content: `message ${id}`,
    status: 'sent',
    createdAt,
  };
}

beforeEach(() => {
  storage.__store.clear();
});

test('thread snapshots use schema version 1 and restore recent thread messages', async () => {
  const older = makeThread('older', '1970-01-01T00:00:00.000Z');
  const newer = makeThread('newer', '1970-01-02T00:00:00.000Z');
  await saveThreadsSnapshot(webId, [older, newer]);
  await saveRecentThreadId(webId, older.id);
  await saveMessagesSnapshot(webId, older.id, [
    makeMessage('m1', older.id, '1970-01-01T00:00:00.000Z'),
  ]);

  const raw = storage.__store.get(`${LINX_STORAGE_KEYS.threadsSnapshot}:${webId}`);
  expect(raw).toBeTruthy();
  expect(JSON.parse(raw!).schemaVersion).toBe(1);

  const snapshot = await loadLaunchSnapshot(webId);
  expect(snapshot?.threads.map(thread => thread.id)).toEqual(['newer', 'older']);
  expect(snapshot?.selectedThread?.id).toBe('older');
  expect(snapshot?.messages.map(message => message.id)).toEqual(['m1']);
});

test('message snapshots are sorted, limited, and isolated by thread', async () => {
  const threadId = 'thread-1';
  const messages = Array.from({ length: LINX_CONTRACT.pageSize + 1 }, (_, index) =>
    makeMessage(
      `m-${String(index).padStart(2, '0')}`,
      threadId,
      new Date(Date.UTC(1970, 0, 1, 0, 0, index)).toISOString(),
    ),
  ).reverse();

  await saveMessagesSnapshot(webId, threadId, messages);
  await saveMessagesSnapshot(webId, 'thread-2', [
    makeMessage('other-thread', 'thread-2', '1970-01-01T00:00:00.000Z'),
  ]);

  const loaded = await loadMessagesSnapshot(webId, threadId);
  expect(loaded).toHaveLength(LINX_CONTRACT.pageSize);
  expect(loaded[0].id).toBe('m-01');
  expect(loaded[loaded.length - 1].id).toBe('m-20');
  expect(await loadMessagesSnapshot(webId, 'missing-thread')).toEqual([]);
  expect(await loadMessagesSnapshot(otherWebId, threadId)).toEqual([]);
});

test('corrupt cache entries fall back to empty data without throwing', async () => {
  storage.__store.set(`${LINX_STORAGE_KEYS.threadsSnapshot}:${webId}`, '{bad-json');
  storage.__store.set(
    `${LINX_STORAGE_KEYS.messagesSnapshot}:${webId}:thread-1`,
    JSON.stringify({ schemaVersion: 999, messages: [] }),
  );

  await expect(loadThreadsSnapshot(webId)).resolves.toEqual([]);
  await expect(loadMessagesSnapshot(webId, 'thread-1')).resolves.toEqual([]);
  await expect(loadLaunchSnapshot(webId)).resolves.toBeNull();
});

test('clearUserChatCache removes only the selected user cache', async () => {
  await saveThreadsSnapshot(webId, [makeThread('a', '1970-01-01T00:00:00.000Z')]);
  await saveMessagesSnapshot(webId, 'a', [
    makeMessage('m1', 'a', '1970-01-01T00:00:00.000Z'),
  ]);
  await saveThreadsSnapshot(otherWebId, [
    makeThread('b', '1970-01-02T00:00:00.000Z'),
  ]);

  await clearUserChatCache(webId);

  expect(await loadThreadsSnapshot(webId)).toEqual([]);
  expect(await loadMessagesSnapshot(webId, 'a')).toEqual([]);
  expect((await loadThreadsSnapshot(otherWebId)).map(thread => thread.id)).toEqual([
    'b',
  ]);
});
