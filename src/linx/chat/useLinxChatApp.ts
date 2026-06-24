import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { LINX_CONTRACT } from '../contract';
import { isAuthExpiredError } from '../errors';
import { LinxAuthController } from '../auth/oidc';
import { PodClient } from '../pod/client';
import { PodChatRepository } from '../pod/repository';
import {
  createRemoteCompletion,
  LinxAppAbortError,
  listRemoteModels,
  pickPreferredModelId,
} from '../runtime/chatApi';
import type {
  LinxAuthSession,
  LinxChatMessage,
  LinxLaunchPhase,
  LinxThreadSummary,
  RemoteChatMessage,
} from '../types';
import type { LinxLoginOptions } from '../storageSettings';
import { normalizeCustomStorageServerUrl } from '../storageSettings';
import {
  clearRecentThreadId,
  clearUserChatCache,
  loadLaunchSnapshot,
  loadMessagesSnapshot,
  loadRecentThreadId,
  saveMessagesSnapshot,
  saveRecentThreadId,
  saveThreadsSnapshot,
} from './cache';

export interface LinxChatAppState {
  phase: LinxLaunchPhase;
  session: LinxAuthSession | null;
  activeModelId: string;
  threads: LinxThreadSummary[];
  selectedThread: LinxThreadSummary | null;
  messages: LinxChatMessage[];
  isSending: boolean;
  isLoadingMessages: boolean;
  isUsingCachedFallback: boolean;
  canLoadMoreMessages: boolean;
  errorMessage?: string;
  login(options?: LinxLoginOptions): Promise<void>;
  logout(): Promise<void>;
  retry(): Promise<void>;
  newChat(): Promise<void>;
  selectThread(thread: LinxThreadSummary): Promise<void>;
  sendMessage(text: string): Promise<void>;
  loadMoreMessages(): Promise<void>;
  cancelSend(): void;
  clearError(): void;
}

type MessageLoadResult = 'loaded' | 'preserved-cache';

const EMPTY_THREADS_CACHE_MESSAGE =
  'Pod returned no chat history. Showing cached chat data.';
const EMPTY_MESSAGES_CACHE_MESSAGE =
  'Pod returned no messages for this thread. Showing cached messages.';

function toRemoteMessages(messages: LinxChatMessage[]): RemoteChatMessage[] {
  return messages
    .filter(message =>
      ['system', 'user', 'assistant'].includes(message.role),
    )
    .sort((left, right) => {
      const dateComparison = left.createdAt.localeCompare(right.createdAt);
      return dateComparison === 0
        ? left.id.localeCompare(right.id)
        : dateComparison;
    })
    .map(message => ({
      role: message.role,
      content: message.content,
    }));
}

function resolveErrorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
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

function mergeMessages(
  loaded: LinxChatMessage[],
  current: LinxChatMessage[],
  threadId: string,
): LinxChatMessage[] {
  const seenIds = new Set(loaded.map(message => message.id));
  const merged = [...loaded];

  for (const message of current) {
    if (message.threadId === threadId && !seenIds.has(message.id)) {
      seenIds.add(message.id);
      merged.push(message);
    }
  }

  return sortMessages(merged);
}

export function useLinxChatApp(): LinxChatAppState {
  const authController = useMemo(() => new LinxAuthController(), []);
  const repository = useMemo(
    () => new PodChatRepository(new PodClient(authController)),
    [authController],
  );

  const sendAbortController = useRef<AbortController | null>(null);
  const messageLoadId = useRef(0);
  const loadedMessageLimit = useRef(LINX_CONTRACT.pageSize);
  const messagesRef = useRef<LinxChatMessage[]>([]);
  const selectedThreadRef = useRef<LinxThreadSummary | null>(null);
  const threadsRef = useRef<LinxThreadSummary[]>([]);

  const [phase, setPhase] = useState<LinxLaunchPhase>('restoring');
  const [session, setSession] = useState<LinxAuthSession | null>(null);
  const [activeModelId, setActiveModelId] = useState<string>(
    LINX_CONTRACT.defaultModelId,
  );
  const [threads, setThreads] = useState<LinxThreadSummary[]>([]);
  const [selectedThread, setSelectedThread] = useState<LinxThreadSummary | null>(
    null,
  );
  const [messages, setMessages] = useState<LinxChatMessage[]>([]);
  const [isSending, setIsSending] = useState(false);
  const [isLoadingMessages, setIsLoadingMessages] = useState(false);
  const [hasLoadedAllMessages, setHasLoadedAllMessages] = useState(true);
  const [isUsingCachedFallback, setIsUsingCachedFallback] = useState(false);
  const [errorMessage, setErrorMessage] = useState<string | undefined>();

  const setThreadsState = useCallback((next: LinxThreadSummary[]) => {
    const sorted = sortThreads(next);
    threadsRef.current = sorted;
    setThreads(sorted);
  }, []);

  const setSelectedThreadState = useCallback((next: LinxThreadSummary | null) => {
    selectedThreadRef.current = next;
    setSelectedThread(next);
  }, []);

  const setMessagesState = useCallback((next: LinxChatMessage[]) => {
    const sorted = sortMessages(next);
    messagesRef.current = sorted;
    setMessages(sorted);
  }, []);

  const invalidateMessageLoads = useCallback(() => {
    messageLoadId.current += 1;
  }, []);

  const resetMessagePaging = useCallback((hasLoadedAll = true) => {
    loadedMessageLimit.current = LINX_CONTRACT.pageSize;
    setHasLoadedAllMessages(hasLoadedAll);
  }, []);

  const resetChatState = useCallback(() => {
    sendAbortController.current?.abort();
    sendAbortController.current = null;
    invalidateMessageLoads();
    setThreadsState([]);
    setSelectedThreadState(null);
    setMessagesState([]);
    setIsSending(false);
    setIsLoadingMessages(false);
    setIsUsingCachedFallback(false);
    resetMessagePaging(true);
    setActiveModelId(LINX_CONTRACT.defaultModelId);
  }, [
    invalidateMessageLoads,
    resetMessagePaging,
    setMessagesState,
    setSelectedThreadState,
    setThreadsState,
  ]);

  const handleAuthExpired = useCallback(async () => {
    await authController.expireSession();
    setSession(null);
    resetChatState();
    setErrorMessage('LinX Cloud login expired.');
    setPhase('unauthenticated');
  }, [authController, resetChatState]);

  const applyLaunchSnapshot = useCallback(
    async (webId: string): Promise<boolean> => {
      const snapshot = await loadLaunchSnapshot(webId, LINX_CONTRACT.pageSize);
      if (!snapshot) {
        return false;
      }

      setThreadsState(snapshot.threads);
      setSelectedThreadState(snapshot.selectedThread);
      setMessagesState(snapshot.messages);
      resetMessagePaging(
        !snapshot.selectedThread ||
          snapshot.messages.length < LINX_CONTRACT.pageSize,
      );
      return true;
    },
    [
      resetMessagePaging,
      setMessagesState,
      setSelectedThreadState,
      setThreadsState,
    ],
  );

  const hasVisibleChatData = useCallback(
    () =>
      threadsRef.current.length > 0 ||
      Boolean(selectedThreadRef.current) ||
      messagesRef.current.length > 0,
    [],
  );

  const resolvePreferredModelId = useCallback(
    async (nextSession: LinxAuthSession): Promise<string> => {
      try {
        const models = await listRemoteModels({
          issuerUrl: nextSession.issuerUrl,
          tokenProvider: authController,
        });
        return pickPreferredModelId(models);
      } catch {
        return LINX_CONTRACT.defaultModelId;
      }
    },
    [authController],
  );

  const loadMessagesForThread = useCallback(
    async (
      currentSession: LinxAuthSession,
      thread: LinxThreadSummary,
      limit: number = loadedMessageLimit.current,
    ): Promise<MessageLoadResult> => {
      const requestId = messageLoadId.current + 1;
      messageLoadId.current = requestId;
      setIsLoadingMessages(true);

      try {
        const loaded = await repository.loadMessages(currentSession, thread.id, limit);
        if (
          messageLoadId.current !== requestId ||
          selectedThreadRef.current?.id !== thread.id
        ) {
          return 'loaded';
        }

        if (
          loaded.length === 0 &&
          messagesRef.current.some(message => message.threadId === thread.id)
        ) {
          setHasLoadedAllMessages(messagesRef.current.length < limit);
          setIsUsingCachedFallback(true);
          setErrorMessage(EMPTY_MESSAGES_CACHE_MESSAGE);
          return 'preserved-cache';
        }

        const nextMessages = mergeMessages(loaded, messagesRef.current, thread.id);
        setMessagesState(nextMessages);
        setHasLoadedAllMessages(loaded.length < limit);
        setIsUsingCachedFallback(false);
        setErrorMessage(undefined);
        await saveMessagesSnapshot(currentSession.webId, thread.id, nextMessages);
        await saveRecentThreadId(currentSession.webId, thread.id);
        return 'loaded';
      } catch (error) {
        if (isAuthExpiredError(error)) {
          throw error;
        }

        if (
          messageLoadId.current !== requestId ||
          selectedThreadRef.current?.id !== thread.id
        ) {
          return 'loaded';
        }

        const cachedMessages = await loadMessagesSnapshot(currentSession.webId, thread.id, limit);
        if (cachedMessages.length > 0) {
          setMessagesState(cachedMessages);
          setHasLoadedAllMessages(cachedMessages.length < limit);
          setIsUsingCachedFallback(true);
          setErrorMessage(resolveErrorMessage(error));
          return 'preserved-cache';
        }

        setErrorMessage(resolveErrorMessage(error));
        throw error;
      } finally {
        if (messageLoadId.current === requestId) {
          setIsLoadingMessages(false);
        }
      }
    },
    [repository, setMessagesState],
  );

  const bootstrap = useCallback(
    async (nextSession: LinxAuthSession): Promise<void> => {
      setPhase('bootstrapping');
      setErrorMessage(undefined);
      setIsUsingCachedFallback(false);
      setSession(nextSession);

      const didApplyCache = await applyLaunchSnapshot(nextSession.webId);

      try {
        const [modelId] = await Promise.all([
          resolvePreferredModelId(nextSession),
          repository.bootstrap(nextSession, LINX_CONTRACT.defaultModelId),
        ]);
        setActiveModelId(modelId);

        const loadedThreads = await repository.listThreads(nextSession);
        const sortedThreads = sortThreads(loadedThreads);

        if (sortedThreads.length === 0 && (didApplyCache || hasVisibleChatData())) {
          setIsUsingCachedFallback(true);
          setErrorMessage(EMPTY_THREADS_CACHE_MESSAGE);
          setPhase('ready');
          return;
        }

        setThreadsState(sortedThreads);
        await saveThreadsSnapshot(nextSession.webId, sortedThreads);

        const recentThreadId = await loadRecentThreadId(nextSession.webId);
        const currentThreadId = selectedThreadRef.current?.id;
        const threadToSelect =
          sortedThreads.find(thread => thread.id === currentThreadId) ??
          sortedThreads.find(thread => thread.id === recentThreadId) ??
          sortedThreads[0] ??
          null;

        setSelectedThreadState(threadToSelect);
        resetMessagePaging(!threadToSelect);

        if (threadToSelect) {
          const loadResult = await loadMessagesForThread(
            nextSession,
            threadToSelect,
            LINX_CONTRACT.pageSize,
          );
          setIsUsingCachedFallback(loadResult === 'preserved-cache');
        } else {
          setMessagesState([]);
          setHasLoadedAllMessages(true);
        }

        setPhase('ready');
      } catch (error) {
        if (isAuthExpiredError(error)) {
          await handleAuthExpired();
          return;
        }

        if (didApplyCache || hasVisibleChatData()) {
          setIsUsingCachedFallback(true);
          setErrorMessage(resolveErrorMessage(error));
          setPhase('ready');
          return;
        }

        setErrorMessage(resolveErrorMessage(error));
        setPhase('error');
      }
    },
    [
      applyLaunchSnapshot,
      handleAuthExpired,
      hasVisibleChatData,
      loadMessagesForThread,
      repository,
      resetMessagePaging,
      resolvePreferredModelId,
      setMessagesState,
      setSelectedThreadState,
      setThreadsState,
    ],
  );

  useEffect(() => {
    let cancelled = false;
    authController
      .restore()
      .then(restored => {
        if (cancelled) {
          return;
        }
        if (!restored) {
          setPhase('unauthenticated');
          return;
        }
        bootstrap(restored).catch(error => {
          if (cancelled) {
            return;
          }
          setErrorMessage(resolveErrorMessage(error));
          setPhase('error');
        });
      })
      .catch(error => {
        if (cancelled) {
          return;
        }
        setErrorMessage(resolveErrorMessage(error));
        setPhase('error');
      });

    return () => {
      cancelled = true;
      sendAbortController.current?.abort();
      invalidateMessageLoads();
    };
  }, [authController, bootstrap, invalidateMessageLoads]);

  const login = useCallback(async (options: LinxLoginOptions = {}) => {
    setPhase('authenticating');
    setErrorMessage(undefined);
    setIsUsingCachedFallback(false);
    try {
      const storageServerUrl = normalizeCustomStorageServerUrl(options.storageServerUrl);
      const loggedInSession = await authController.login();
      const nextSession = storageServerUrl
        ? { ...loggedInSession, storageServerUrl }
        : loggedInSession;
      await bootstrap(nextSession);
    } catch (error) {
      setErrorMessage(resolveErrorMessage(error));
      setPhase('unauthenticated');
    }
  }, [authController, bootstrap]);

  const logout = useCallback(async () => {
    const webId = session?.webId;
    await authController.logout();
    if (webId) {
      await clearRecentThreadId(webId);
      await clearUserChatCache(webId);
    }
    setSession(null);
    resetChatState();
    setErrorMessage(undefined);
    setPhase('unauthenticated');
  }, [authController, resetChatState, session?.webId]);

  const retry = useCallback(async () => {
    const current = session ?? (await authController.getSession());
    if (current) {
      await bootstrap(current);
      return;
    }
    setPhase('unauthenticated');
  }, [authController, bootstrap, session]);

  const newChat = useCallback(async () => {
    if (!session) {
      return;
    }
    sendAbortController.current?.abort();
    invalidateMessageLoads();
    setSelectedThreadState(null);
    setMessagesState([]);
    resetMessagePaging(true);
    setIsLoadingMessages(false);
    setIsSending(false);
    setIsUsingCachedFallback(false);
    setErrorMessage(undefined);
    await clearRecentThreadId(session.webId);
  }, [
    invalidateMessageLoads,
    resetMessagePaging,
    session,
    setMessagesState,
    setSelectedThreadState,
  ]);

  const selectThread = useCallback(
    async (thread: LinxThreadSummary) => {
      if (!session) {
        return;
      }

      invalidateMessageLoads();
      setSelectedThreadState(thread);
      setMessagesState([]);
      resetMessagePaging(false);
      setErrorMessage(undefined);
      setIsUsingCachedFallback(false);

      const cachedMessages = await loadMessagesSnapshot(
        session.webId,
        thread.id,
        LINX_CONTRACT.pageSize,
      );
      if (selectedThreadRef.current?.id === thread.id && cachedMessages.length > 0) {
        setMessagesState(cachedMessages);
        setHasLoadedAllMessages(cachedMessages.length < LINX_CONTRACT.pageSize);
      }

      try {
        await loadMessagesForThread(session, thread, LINX_CONTRACT.pageSize);
      } catch (error) {
        if (isAuthExpiredError(error)) {
          await handleAuthExpired();
        }
      }
    },
    [
      handleAuthExpired,
      invalidateMessageLoads,
      loadMessagesForThread,
      resetMessagePaging,
      session,
      setMessagesState,
      setSelectedThreadState,
    ],
  );

  const sendMessage = useCallback(
    async (text: string) => {
      const trimmed = text.trim();
      if (!session || !trimmed || isSending || phase === 'bootstrapping') {
        return;
      }

      setIsSending(true);
      setErrorMessage(undefined);
      setIsUsingCachedFallback(false);
      const abortController = new AbortController();
      sendAbortController.current = abortController;

      try {
        let thread = selectedThreadRef.current;
        if (!thread) {
          const createdThread = await repository.createThread(session);
          thread = createdThread;
          setThreadsState([createdThread, ...threadsRef.current]);
          setSelectedThreadState(createdThread);
          resetMessagePaging(true);
          await saveThreadsSnapshot(session.webId, threadsRef.current);
          await saveRecentThreadId(session.webId, createdThread.id);
        }

        const persistedHistory = await repository.loadMessages(session, thread.id);
        const userMessage = await repository.appendUserMessage(
          session,
          thread.id,
          trimmed,
        );

        if (selectedThreadRef.current?.id === thread.id) {
          const nextMessages = sortMessages([...messagesRef.current, userMessage]);
          setMessagesState(nextMessages);
          await saveMessagesSnapshot(session.webId, thread.id, nextMessages);
        }

        const completion = await createRemoteCompletion({
          issuerUrl: session.issuerUrl,
          tokenProvider: authController,
          model: activeModelId,
          messages: [
            ...toRemoteMessages(persistedHistory),
            { role: 'user', content: trimmed },
          ],
          signal: abortController.signal,
        });

        const assistantMessage = await repository.appendAssistantMessage(
          session,
          thread.id,
          completion.content,
        );

        if (selectedThreadRef.current?.id === thread.id) {
          const nextMessages = sortMessages([
            ...messagesRef.current,
            assistantMessage,
          ]);
          setMessagesState(nextMessages);
          await saveMessagesSnapshot(session.webId, thread.id, nextMessages);
        }

        const refreshedThreads = await repository.listThreads(session);
        if (refreshedThreads.length > 0) {
          setThreadsState(refreshedThreads);
          await saveThreadsSnapshot(session.webId, threadsRef.current);
          const refreshedSelected = threadsRef.current.find(
            candidate => candidate.id === thread?.id,
          );
          if (refreshedSelected) {
            setSelectedThreadState(refreshedSelected);
          }
        }
        setHasLoadedAllMessages(messagesRef.current.length < loadedMessageLimit.current);
        await saveRecentThreadId(session.webId, thread.id);
        setPhase('ready');
      } catch (error) {
        if (error instanceof LinxAppAbortError) {
          setErrorMessage(error.message);
          return;
        }
        if (isAuthExpiredError(error)) {
          await handleAuthExpired();
          return;
        }
        setErrorMessage(resolveErrorMessage(error));
      } finally {
        if (sendAbortController.current === abortController) {
          sendAbortController.current = null;
        }
        setIsSending(false);
      }
    },
    [
      activeModelId,
      authController,
      handleAuthExpired,
      isSending,
      phase,
      repository,
      resetMessagePaging,
      session,
      setMessagesState,
      setSelectedThreadState,
      setThreadsState,
    ],
  );

  const loadMoreMessages = useCallback(async () => {
    if (!session || !selectedThreadRef.current || isLoadingMessages || hasLoadedAllMessages) {
      return;
    }

    loadedMessageLimit.current += LINX_CONTRACT.pageSize;
    try {
      await loadMessagesForThread(
        session,
        selectedThreadRef.current,
        loadedMessageLimit.current,
      );
    } catch (error) {
      if (isAuthExpiredError(error)) {
        await handleAuthExpired();
      }
    }
  }, [
    handleAuthExpired,
    hasLoadedAllMessages,
    isLoadingMessages,
    loadMessagesForThread,
    session,
  ]);

  const cancelSend = useCallback(() => {
    sendAbortController.current?.abort();
  }, []);

  const clearError = useCallback(() => {
    setErrorMessage(undefined);
  }, []);

  return {
    phase,
    session,
    activeModelId,
    threads,
    selectedThread,
    messages,
    isSending,
    isLoadingMessages,
    isUsingCachedFallback,
    canLoadMoreMessages:
      Boolean(selectedThread) && !hasLoadedAllMessages && !isLoadingMessages,
    errorMessage,
    login,
    logout,
    retry,
    newChat,
    selectThread,
    sendMessage,
    loadMoreMessages,
    cancelSend,
    clearError,
  };
}
