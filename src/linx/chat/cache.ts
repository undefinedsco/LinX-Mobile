import AsyncStorage from '@react-native-async-storage/async-storage';
import { LINX_STORAGE_KEYS } from '../contract';

function keyForRecentThread(webId: string): string {
  return `${LINX_STORAGE_KEYS.recentThreadId}:${webId}`;
}

export async function loadRecentThreadId(webId: string): Promise<string | null> {
  return AsyncStorage.getItem(keyForRecentThread(webId));
}

export async function saveRecentThreadId(
  webId: string,
  threadId: string,
): Promise<void> {
  await AsyncStorage.setItem(keyForRecentThread(webId), threadId);
}

export async function clearRecentThreadId(webId: string): Promise<void> {
  await AsyncStorage.removeItem(keyForRecentThread(webId));
}
