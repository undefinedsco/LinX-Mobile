import React, { useEffect, useRef, useState } from 'react';
import {
  ActivityIndicator,
  FlatList,
  KeyboardAvoidingView,
  Modal,
  Platform,
  Pressable,
  StyleSheet,
  Text,
  TextInput,
  useColorScheme,
  View,
  type ListRenderItemInfo,
} from 'react-native';
import Markdown from 'react-native-markdown-display';
import type { LinxChatAppState } from '../chat/useLinxChatApp';
import type { LinxChatMessage } from '../types';
import { P2PSmokeScreen } from '../../p2p-smoke/P2PSmokeScreen';
import { p2pSmokeDefaultsFromSession } from '../../p2p-smoke/p2pSmokeDefaultsFromSession';
import { LinxPalette, linxColors } from './LinxPalette';
import { ThreadListSheet } from './ThreadListSheet';

type ChatScreenProps = LinxChatAppState;

function ignorePromise(promise: Promise<unknown> | void): void {
  Promise.resolve(promise).catch(() => undefined);
}

function MessageBubble({
  message,
  isDark,
}: {
  message: LinxChatMessage;
  isDark: boolean;
}) {
  const colors = linxColors(isDark);
  const isUser = message.role === 'user';
  return (
    <View
      style={[
        styles.messageRow,
        isUser ? styles.messageRowUser : styles.messageRowAssistant,
      ]}>
      {!isUser ? (
        <View style={[styles.avatar, { backgroundColor: LinxPalette.accent }]}>
          <Text style={styles.avatarText}>L</Text>
        </View>
      ) : null}
      <View
        style={[
          styles.messageBubble,
          isUser
            ? { backgroundColor: LinxPalette.accent }
            : {
                backgroundColor: colors.elevatedSurface,
                borderColor: colors.border,
                borderWidth: StyleSheet.hairlineWidth,
              },
        ]}>
        {isUser ? (
          <Text style={styles.userMessageText}>{message.content}</Text>
        ) : (
          <Markdown
            style={{
              body: isDark ? styles.markdownBodyDark : styles.markdownBody,
              paragraph: styles.markdownParagraph,
            }}>
            {message.content}
          </Markdown>
        )}
      </View>
      {isUser ? (
        <View style={[styles.avatar, { backgroundColor: LinxPalette.blue }]}>
          <Text style={styles.avatarText}>ME</Text>
        </View>
      ) : null}
    </View>
  );
}

function ErrorBanner({
  message,
  canRetry,
  onRetry,
  onDismiss,
}: {
  message: string;
  canRetry: boolean;
  onRetry: () => void;
  onDismiss: () => void;
}) {
  return (
    <View style={styles.errorBar}>
      <Text accessibilityRole="alert" style={styles.errorText}>
        {message}
      </Text>
      {canRetry ? (
        <Pressable
          accessibilityRole="button"
          onPress={onRetry}
          style={styles.errorButton}>
          <Text style={styles.errorButtonText}>Retry</Text>
        </Pressable>
      ) : null}
      <Pressable
        accessibilityRole="button"
        onPress={onDismiss}
        style={styles.errorButton}
        testID="dismiss-error-button">
        <Text style={styles.errorButtonText}>Dismiss</Text>
      </Pressable>
    </View>
  );
}

export function ChatScreen(props: ChatScreenProps) {
  const isDark = useColorScheme() === 'dark';
  const colors = linxColors(isDark);
  const [draft, setDraft] = useState('');
  const [showThreads, setShowThreads] = useState(false);
  const [showP2PSmoke, setShowP2PSmoke] = useState(false);
  const listRef = useRef<FlatList<LinxChatMessage>>(null);
  const lastMessageId = props.messages[props.messages.length - 1]?.id;
  const lastScrolledMessageId = useRef<string | undefined>(undefined);

  useEffect(() => {
    if (!lastMessageId || lastScrolledMessageId.current === lastMessageId) {
      return;
    }
    lastScrolledMessageId.current = lastMessageId;
    requestAnimationFrame(() => {
      listRef.current?.scrollToEnd({ animated: true });
    });
  }, [lastMessageId]);

  const send = () => {
    const next = draft.trim();
    if (!next) {
      return;
    }
    setDraft('');
    ignorePromise(props.sendMessage(next));
  };

  const subtitle = props.isSending
    ? 'Responding'
    : props.isUsingCachedFallback
      ? 'Cached Pod'
      : props.activeModelId;

  const renderMessage = ({ item }: ListRenderItemInfo<LinxChatMessage>) => (
    <MessageBubble isDark={isDark} message={item} />
  );

  return (
    <KeyboardAvoidingView
      behavior={Platform.OS === 'ios' ? 'padding' : undefined}
      style={[styles.container, { backgroundColor: colors.background }]}>
      <View
        style={[
          styles.header,
          { backgroundColor: colors.backgroundAlt, borderBottomColor: colors.border },
        ]}>
        <Pressable
          accessibilityLabel="Show chats"
          accessibilityRole="button"
          onPress={() => setShowThreads(true)}
          style={styles.headerButton}>
          <Text style={[styles.headerButtonText, { color: LinxPalette.accent }]}>
            Chats
          </Text>
        </Pressable>
        <View style={styles.headerTitleWrap}>
          <Text numberOfLines={1} style={[styles.headerTitle, { color: colors.text }]}>
            {props.selectedThread?.title ?? 'LinX'}
          </Text>
          <View style={styles.subtitleRow}>
            <View
              style={[
                styles.statusDot,
                {
                  backgroundColor: props.isSending
                    ? LinxPalette.blue
                    : LinxPalette.accent,
                },
              ]}
            />
            <Text numberOfLines={1} style={[styles.modelText, { color: colors.secondaryText }]}>
              {subtitle}
            </Text>
          </View>
        </View>
        <Pressable
          accessibilityLabel="New chat"
          accessibilityRole="button"
          onPress={() => {
            ignorePromise(props.newChat());
          }}
          style={styles.headerButton}>
          <Text style={[styles.headerButtonText, { color: LinxPalette.accent }]}>
            New
          </Text>
        </Pressable>
      </View>

      {props.errorMessage ? (
        <ErrorBanner
          canRetry={props.phase === 'error' || props.isUsingCachedFallback}
          message={props.errorMessage}
          onDismiss={props.clearError}
          onRetry={() => {
            ignorePromise(props.retry());
          }}
        />
      ) : null}

      {props.phase === 'bootstrapping' || props.isLoadingMessages ? (
        <View
          pointerEvents="none"
          style={[
            styles.loadingOverlay,
            { backgroundColor: colors.backgroundAlt, borderBottomColor: colors.border },
          ]}>
          <ActivityIndicator color={LinxPalette.accent} />
          <Text style={[styles.loadingText, { color: colors.secondaryText }]}>
            Syncing your Pod
          </Text>
        </View>
      ) : null}

      <FlatList
        ref={listRef}
        contentContainerStyle={styles.messageList}
        data={props.messages}
        keyExtractor={item => item.id}
        keyboardShouldPersistTaps="handled"
        ListEmptyComponent={
          <View style={styles.emptyState}>
            <Text style={[styles.emptyTitle, { color: colors.text }]}>
              Start a chat
            </Text>
            <Text style={[styles.emptySubtitle, { color: colors.secondaryText }]}>
              Messages are stored in your Solid Pod.
            </Text>
          </View>
        }
        ListHeaderComponent={
          props.canLoadMoreMessages ? (
            <Pressable
              accessibilityRole="button"
              disabled={props.isLoadingMessages}
              onPress={() => {
                ignorePromise(props.loadMoreMessages());
              }}
              style={[
                styles.loadMoreButton,
                { backgroundColor: colors.surface, borderColor: colors.border },
              ]}>
              <Text style={[styles.loadMoreText, { color: LinxPalette.accent }]}>
                Load earlier messages
              </Text>
            </Pressable>
          ) : null
        }
        renderItem={renderMessage}
      />

      {props.isSending ? (
        <View style={[styles.sendingBar, { backgroundColor: colors.surface }]}>
          <ActivityIndicator color={LinxPalette.accent} size="small" />
          <Text style={[styles.sendingText, { color: colors.text }]}>
            LinX is responding
          </Text>
          <Pressable
            accessibilityRole="button"
            onPress={props.cancelSend}
            style={styles.inlineCancelButton}>
            <Text style={styles.inlineCancelText}>Stop</Text>
          </Pressable>
        </View>
      ) : null}

      <View
        style={[
          styles.composer,
          { backgroundColor: colors.backgroundAlt, borderTopColor: colors.border },
        ]}>
        <TextInput
          multiline
          editable={!props.isSending && props.phase !== 'bootstrapping'}
          onChangeText={setDraft}
          placeholder="Message LinX"
          placeholderTextColor={colors.tertiaryText}
          style={[
            styles.input,
            {
              backgroundColor: colors.input,
              borderColor: colors.border,
              color: colors.text,
            },
          ]}
          testID="message-input"
          value={draft}
        />
        <Pressable
          accessibilityRole="button"
          disabled={!draft.trim() || props.isSending || props.phase === 'bootstrapping'}
          onPress={send}
          style={({ pressed }) => [
            styles.sendButton,
            pressed && styles.sendButtonPressed,
            (!draft.trim() || props.isSending || props.phase === 'bootstrapping') &&
              styles.sendButtonDisabled,
          ]}
          testID="send-button">
          <Text style={styles.sendButtonText}>Send</Text>
        </Pressable>
      </View>

      <ThreadListSheet
        isDark={isDark}
        onClose={() => setShowThreads(false)}
        onLogout={() => {
          setShowThreads(false);
          ignorePromise(props.logout());
        }}
        onNewChat={() => {
          setShowThreads(false);
          ignorePromise(props.newChat());
        }}
        onOpenP2PSmoke={() => {
          setShowThreads(false);
          setShowP2PSmoke(true);
        }}
        onSelectThread={thread => {
          setShowThreads(false);
          ignorePromise(props.selectThread(thread));
        }}
        selectedThreadId={props.selectedThread?.id}
        threads={props.threads}
        visible={showThreads}
      />
      <Modal
        animationType="slide"
        onRequestClose={() => setShowP2PSmoke(false)}
        visible={showP2PSmoke}>
        <View style={[styles.p2pModal, { backgroundColor: colors.background }]}>
          <View
            style={[
              styles.p2pHeader,
              {
                backgroundColor: colors.backgroundAlt,
                borderBottomColor: colors.border,
              },
            ]}>
            <Pressable
              accessibilityRole="button"
              onPress={() => setShowP2PSmoke(false)}
              style={styles.p2pBackButton}>
              <Text style={[styles.headerButtonText, { color: LinxPalette.accent }]}>
                Back to chat
              </Text>
            </Pressable>
          </View>
          <P2PSmokeScreen
            embeddedInChat
            initialSession={props.session}
            initialSmokeDefaults={p2pSmokeDefaultsFromSession(props.session)}
          />
        </View>
      </Modal>
    </KeyboardAvoidingView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
  },
  header: {
    alignItems: 'center',
    borderBottomWidth: StyleSheet.hairlineWidth,
    flexDirection: 'row',
    gap: 10,
    paddingHorizontal: 12,
    paddingVertical: 10,
  },
  headerButton: {
    borderRadius: 8,
    minWidth: 54,
    paddingHorizontal: 8,
    paddingVertical: 8,
  },
  headerButtonText: {
    fontSize: 15,
    fontWeight: '800',
  },
  headerTitleWrap: {
    alignItems: 'center',
    flex: 1,
    minWidth: 0,
  },
  headerTitle: {
    fontSize: 17,
    fontWeight: '800',
    letterSpacing: 0,
    lineHeight: 22,
    textAlign: 'center',
  },
  subtitleRow: {
    alignItems: 'center',
    flexDirection: 'row',
    gap: 6,
    maxWidth: 220,
    minWidth: 0,
  },
  statusDot: {
    borderRadius: 3,
    height: 6,
    width: 6,
  },
  modelText: {
    flexShrink: 1,
    fontSize: 12,
    fontWeight: '700',
    marginTop: 1,
    textAlign: 'center',
  },
  errorBar: {
    alignItems: 'center',
    backgroundColor: LinxPalette.warning,
    flexDirection: 'row',
    gap: 8,
    marginHorizontal: 12,
    marginTop: 8,
    borderRadius: 14,
    paddingHorizontal: 12,
    paddingVertical: 10,
  },
  errorText: {
    color: '#fff',
    flex: 1,
    fontSize: 13,
    fontWeight: '600',
    lineHeight: 18,
  },
  errorButton: {
    borderColor: 'rgba(255,255,255,0.58)',
    borderRadius: 8,
    borderWidth: 1,
    paddingHorizontal: 8,
    paddingVertical: 5,
  },
  errorButtonText: {
    color: '#fff',
    fontSize: 12,
    fontWeight: '800',
  },
  loadingOverlay: {
    alignItems: 'center',
    borderBottomWidth: StyleSheet.hairlineWidth,
    flexDirection: 'row',
    gap: 8,
    justifyContent: 'center',
    minHeight: 38,
  },
  loadingText: {
    fontSize: 12,
    fontWeight: '700',
  },
  messageList: {
    flexGrow: 1,
    gap: 12,
    padding: 12,
  },
  loadMoreButton: {
    alignItems: 'center',
    alignSelf: 'center',
    borderRadius: 999,
    borderWidth: 1,
    marginBottom: 8,
    paddingHorizontal: 14,
    paddingVertical: 8,
  },
  loadMoreText: {
    fontSize: 13,
    fontWeight: '800',
  },
  emptyState: {
    alignItems: 'center',
    flex: 1,
    justifyContent: 'center',
    minHeight: 300,
    padding: 24,
  },
  emptyTitle: {
    fontSize: 18,
    fontWeight: '800',
    marginBottom: 6,
  },
  emptySubtitle: {
    fontSize: 14,
    lineHeight: 20,
    textAlign: 'center',
  },
  messageRow: {
    alignItems: 'flex-end',
    flexDirection: 'row',
    gap: 8,
  },
  messageRowUser: {
    justifyContent: 'flex-end',
  },
  messageRowAssistant: {
    justifyContent: 'flex-start',
  },
  avatar: {
    alignItems: 'center',
    borderRadius: 17,
    height: 34,
    justifyContent: 'center',
    width: 34,
  },
  avatarText: {
    color: '#fff',
    fontSize: 11,
    fontWeight: '900',
  },
  messageBubble: {
    borderRadius: 16,
    maxWidth: '78%',
    paddingHorizontal: 12,
    paddingVertical: 10,
  },
  userMessageText: {
    color: '#fff',
    fontSize: 16,
    lineHeight: 22,
  },
  markdownBody: {
    color: LinxPalette.light.text,
    fontSize: 16,
    lineHeight: 22,
  },
  markdownBodyDark: {
    color: LinxPalette.dark.text,
    fontSize: 16,
    lineHeight: 22,
  },
  markdownParagraph: {
    marginBottom: 0,
    marginTop: 0,
  },
  sendingBar: {
    alignItems: 'center',
    flexDirection: 'row',
    gap: 10,
    paddingHorizontal: 14,
    paddingVertical: 9,
  },
  sendingText: {
    flex: 1,
    fontSize: 13,
    fontWeight: '700',
  },
  inlineCancelButton: {
    paddingHorizontal: 8,
    paddingVertical: 4,
  },
  inlineCancelText: {
    color: LinxPalette.warning,
    fontSize: 13,
    fontWeight: '800',
  },
  composer: {
    alignItems: 'flex-end',
    borderTopWidth: StyleSheet.hairlineWidth,
    flexDirection: 'row',
    gap: 10,
    padding: 12,
  },
  input: {
    borderRadius: 14,
    borderWidth: 1,
    flex: 1,
    fontSize: 16,
    lineHeight: 22,
    maxHeight: 132,
    minHeight: 46,
    paddingHorizontal: 12,
    paddingVertical: 10,
  },
  sendButton: {
    alignItems: 'center',
    backgroundColor: LinxPalette.accent,
    borderRadius: 14,
    justifyContent: 'center',
    minHeight: 46,
    minWidth: 68,
    paddingHorizontal: 14,
  },
  sendButtonPressed: {
    backgroundColor: LinxPalette.accentPressed,
  },
  sendButtonDisabled: {
    opacity: 0.42,
  },
  sendButtonText: {
    color: '#fff',
    fontSize: 15,
    fontWeight: '900',
  },
  p2pModal: {
    flex: 1,
  },
  p2pHeader: {
    borderBottomWidth: StyleSheet.hairlineWidth,
    paddingHorizontal: 12,
    paddingTop: 52,
    paddingBottom: 10,
  },
  p2pBackButton: {
    alignSelf: 'flex-start',
    paddingHorizontal: 8,
    paddingVertical: 8,
  },
});
