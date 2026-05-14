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
import {
  clearRecentThreadId,
  loadRecentThreadId,
  saveRecentThreadId,
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
  errorMessage?: string;
  login(): Promise<void>;
  logout(): Promise<void>;
  retry(): Promise<void>;
  newChat(): Promise<void>;
  selectThread(thread: LinxThreadSummary): Promise<void>;
  sendMessage(text: string): Promise<void>;
  cancelSend(): void;
  clearError(): void;
}

function toRemoteMessages(messages: LinxChatMessage[]): RemoteChatMessage[] {
  return messages
    .filter(message =>
      ['system', 'user', 'assistant'].includes(message.role),
    )
    .sort((left, right) => left.createdAt.localeCompare(right.createdAt))
    .map(message => ({
      role: message.role,
      content: message.content,
    }));
}

function resolveErrorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

export function useLinxChatApp(): LinxChatAppState {
  const authController = useMemo(() => new LinxAuthController(), []);
  const repository = useMemo(
    () => new PodChatRepository(new PodClient(authController)),
    [authController],
  );
  const sendAbortController = useRef<AbortController | null>(null);

  const [phase, setPhase] = useState<LinxLaunchPhase>('restoring');
  const [session, setSession] = useState<LinxAuthSession | null>(null);
  const [activeModelId, setActiveModelId] = useState<string>(
    LINX_CONTRACT.defaultModelId,
  );
  const [threads, setThreads] = useState<LinxThreadSummary[]>([]);
  const [selectedThread, setSelectedThread] = useState<LinxThreadSummary | null>(null);
  const [messages, setMessages] = useState<LinxChatMessage[]>([]);
  const [isSending, setIsSending] = useState(false);
  const [isLoadingMessages, setIsLoadingMessages] = useState(false);
  const [errorMessage, setErrorMessage] = useState<string | undefined>();

  const resetChatState = useCallback(() => {
    sendAbortController.current?.abort();
    sendAbortController.current = null;
    setThreads([]);
    setSelectedThread(null);
    setMessages([]);
    setIsSending(false);
    setIsLoadingMessages(false);
    setActiveModelId(LINX_CONTRACT.defaultModelId);
  }, []);

  const handleAuthExpired = useCallback(async () => {
    await authController.expireSession();
    setSession(null);
    resetChatState();
    setErrorMessage('LinX Cloud login expired.');
    setPhase('unauthenticated');
  }, [authController, resetChatState]);

  const loadMessagesForThread = useCallback(
    async (webId: string, thread: LinxThreadSummary): Promise<void> => {
      setIsLoadingMessages(true);
      try {
        const loaded = await repository.loadMessages(
          webId,
          thread.id,
          LINX_CONTRACT.pageSize,
        );
        setMessages(loaded);
        await saveRecentThreadId(webId, thread.id);
      } finally {
        setIsLoadingMessages(false);
      }
    },
    [repository],
  );

  const bootstrap = useCallback(
    async (nextSession: LinxAuthSession): Promise<void> => {
      setPhase('bootstrapping');
      setErrorMessage(undefined);
      setSession(nextSession);

      try {
        let modelId: string = LINX_CONTRACT.defaultModelId;
        try {
          const models = await listRemoteModels({
            issuerUrl: nextSession.issuerUrl,
            tokenProvider: authController,
          });
          modelId = pickPreferredModelId(models);
        } catch {
          modelId = LINX_CONTRACT.defaultModelId;
        }
        setActiveModelId(modelId);

        await repository.bootstrap(nextSession.webId, modelId);
        const loadedThreads = await repository.listThreads(nextSession.webId);
        setThreads(loadedThreads);

        const recentThreadId = await loadRecentThreadId(nextSession.webId);
        const threadToSelect =
          loadedThreads.find(thread => thread.id === recentThreadId) ??
          loadedThreads[0] ??
          null;
        setSelectedThread(threadToSelect);
        if (threadToSelect) {
          await loadMessagesForThread(nextSession.webId, threadToSelect);
        } else {
          setMessages([]);
        }
        setPhase('ready');
      } catch (error) {
        if (isAuthExpiredError(error)) {
          await handleAuthExpired();
          return;
        }
        setErrorMessage(resolveErrorMessage(error));
        setPhase('error');
      }
    },
    [authController, handleAuthExpired, loadMessagesForThread, repository],
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
    };
  }, [authController, bootstrap]);

  const login = useCallback(async () => {
    setPhase('authenticating');
    setErrorMessage(undefined);
    try {
      const nextSession = await authController.login();
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
    setErrorMessage(undefined);
    try {
      const thread = await repository.createThread(session.webId);
      setThreads(current => [thread, ...current]);
      setSelectedThread(thread);
      setMessages([]);
      await saveRecentThreadId(session.webId, thread.id);
    } catch (error) {
      if (isAuthExpiredError(error)) {
        await handleAuthExpired();
        return;
      }
      setErrorMessage(resolveErrorMessage(error));
    }
  }, [handleAuthExpired, repository, session]);

  const selectThread = useCallback(
    async (thread: LinxThreadSummary) => {
      if (!session) {
        return;
      }
      setSelectedThread(thread);
      setErrorMessage(undefined);
      try {
        await loadMessagesForThread(session.webId, thread);
      } catch (error) {
        if (isAuthExpiredError(error)) {
          await handleAuthExpired();
          return;
        }
        setErrorMessage(resolveErrorMessage(error));
      }
    },
    [handleAuthExpired, loadMessagesForThread, session],
  );

  const sendMessage = useCallback(
    async (text: string) => {
      const trimmed = text.trim();
      if (!session || !trimmed || isSending) {
        return;
      }

      setIsSending(true);
      setErrorMessage(undefined);
      const abortController = new AbortController();
      sendAbortController.current = abortController;

      try {
        let thread = selectedThread;
        if (!thread) {
          const createdThread = await repository.createThread(session.webId);
          thread = createdThread;
          setThreads(current => [createdThread, ...current]);
          setSelectedThread(createdThread);
          await saveRecentThreadId(session.webId, createdThread.id);
        }

        const persistedHistory = await repository.loadMessages(
          session.webId,
          thread.id,
        );
        const userMessage = await repository.appendUserMessage(
          session.webId,
          thread.id,
          trimmed,
        );
        setMessages(current => [...current, userMessage]);

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
          session.webId,
          thread.id,
          completion.content,
        );
        setMessages(current => [...current, assistantMessage]);

        const refreshedThreads = await repository.listThreads(session.webId);
        setThreads(refreshedThreads);
        await saveRecentThreadId(session.webId, thread.id);
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
      repository,
      selectedThread,
      session,
    ],
  );

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
    errorMessage,
    login,
    logout,
    retry,
    newChat,
    selectThread,
    sendMessage,
    cancelSend,
    clearError,
  };
}
