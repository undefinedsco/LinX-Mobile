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
import type { LinxChatMessage, LinxThreadSummary } from '../types';

type ChatScreenProps = LinxChatAppState;

function formatThreadDate(value: string): string {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) {
    return '';
  }
  return date.toLocaleDateString();
}

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
  const isUser = message.role === 'user';
  return (
    <View
      style={[
        styles.messageRow,
        isUser ? styles.messageRowUser : styles.messageRowAssistant,
      ]}>
      <View
        style={[
          styles.messageBubble,
          isUser ? styles.userBubble : styles.assistantBubble,
          isDark && !isUser && styles.assistantBubbleDark,
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
    </View>
  );
}

function ThreadRow({
  thread,
  selected,
  onPress,
}: {
  thread: LinxThreadSummary;
  selected: boolean;
  onPress: () => void;
}) {
  return (
    <Pressable
      accessibilityRole="button"
      onPress={onPress}
      style={[styles.threadRow, selected && styles.threadRowSelected]}>
      <View style={styles.threadText}>
        <Text numberOfLines={1} style={styles.threadTitle}>
          {thread.title}
        </Text>
        <Text numberOfLines={1} style={styles.threadMeta}>
          {formatThreadDate(thread.updatedAt)}
        </Text>
      </View>
      {selected ? <Text style={styles.threadSelectedMark}>Selected</Text> : null}
    </Pressable>
  );
}

export function ChatScreen(props: ChatScreenProps) {
  const isDark = useColorScheme() === 'dark';
  const [draft, setDraft] = useState('');
  const [showThreads, setShowThreads] = useState(false);
  const listRef = useRef<FlatList<LinxChatMessage>>(null);

  useEffect(() => {
    requestAnimationFrame(() => {
      listRef.current?.scrollToEnd({ animated: true });
    });
  }, [props.messages.length]);

  const send = () => {
    const next = draft.trim();
    if (!next) {
      return;
    }
    setDraft('');
    ignorePromise(props.sendMessage(next));
  };

  const renderMessage = ({ item }: ListRenderItemInfo<LinxChatMessage>) => (
    <MessageBubble message={item} isDark={isDark} />
  );

  return (
    <KeyboardAvoidingView
      behavior={Platform.OS === 'ios' ? 'padding' : undefined}
      style={[styles.container, isDark && styles.containerDark]}>
      <View style={[styles.header, isDark && styles.headerDark]}>
        <Pressable
          accessibilityRole="button"
          onPress={() => setShowThreads(true)}
          style={styles.headerButton}>
          <Text style={[styles.headerButtonText, isDark && styles.textDark]}>
            Threads
          </Text>
        </Pressable>
        <View style={styles.headerTitleWrap}>
          <Text
            numberOfLines={1}
            style={[styles.headerTitle, isDark && styles.textDark]}>
            {props.selectedThread?.title ?? 'LinX'}
          </Text>
          <Text numberOfLines={1} style={styles.modelText}>
            {props.activeModelId}
          </Text>
        </View>
        <Pressable
          accessibilityRole="button"
          onPress={() => {
            ignorePromise(props.newChat());
          }}
          style={styles.headerButton}>
          <Text style={[styles.headerButtonText, isDark && styles.textDark]}>
            New
          </Text>
        </Pressable>
      </View>

      {props.errorMessage ? (
        <View style={styles.errorBar}>
          <Text accessibilityRole="alert" style={styles.errorText}>
            {props.errorMessage}
          </Text>
          {props.phase === 'error' ? (
            <Pressable
              accessibilityRole="button"
              onPress={() => {
                ignorePromise(props.retry());
              }}
              style={styles.errorButton}>
              <Text style={styles.errorButtonText}>Retry</Text>
            </Pressable>
          ) : null}
          <Pressable
            accessibilityRole="button"
            onPress={props.clearError}
            style={styles.errorButton}>
            <Text style={styles.errorButtonText}>Dismiss</Text>
          </Pressable>
        </View>
      ) : null}

      {props.phase === 'bootstrapping' || props.isLoadingMessages ? (
        <View style={styles.loadingOverlay} pointerEvents="none">
          <ActivityIndicator />
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
            <Text style={[styles.emptyTitle, isDark && styles.textDark]}>
              Start a chat
            </Text>
          </View>
        }
        renderItem={renderMessage}
      />

      <View style={[styles.composer, isDark && styles.composerDark]}>
        <TextInput
          multiline
          editable={!props.isSending}
          onChangeText={setDraft}
          placeholder="Message LinX"
          placeholderTextColor={isDark ? '#7d8782' : '#7a857f'}
          style={[styles.input, isDark && styles.inputDark]}
          testID="message-input"
          value={draft}
        />
        {props.isSending ? (
          <Pressable
            accessibilityRole="button"
            onPress={props.cancelSend}
            style={[styles.sendButton, styles.cancelButton]}>
            <Text style={styles.sendButtonText}>Cancel</Text>
          </Pressable>
        ) : (
          <Pressable
            accessibilityRole="button"
            disabled={!draft.trim()}
            onPress={send}
            style={[styles.sendButton, !draft.trim() && styles.sendButtonDisabled]}
            testID="send-button">
            <Text style={styles.sendButtonText}>Send</Text>
          </Pressable>
        )}
      </View>

      <Modal
        animationType="slide"
        onRequestClose={() => setShowThreads(false)}
        visible={showThreads}>
        <View style={[styles.modal, isDark && styles.containerDark]}>
          <View style={styles.modalHeader}>
            <Text style={[styles.modalTitle, isDark && styles.textDark]}>
              Threads
            </Text>
            <Pressable
              accessibilityRole="button"
              onPress={() => setShowThreads(false)}
              style={styles.headerButton}>
              <Text style={[styles.headerButtonText, isDark && styles.textDark]}>
                Done
              </Text>
            </Pressable>
          </View>
          <FlatList
            data={props.threads}
            keyExtractor={item => item.id}
            ListEmptyComponent={
              <Text style={[styles.emptyListText, isDark && styles.textDark]}>
                No threads yet.
              </Text>
            }
            renderItem={({ item }) => (
              <ThreadRow
                thread={item}
                selected={item.id === props.selectedThread?.id}
                onPress={() => {
                  setShowThreads(false);
                  ignorePromise(props.selectThread(item));
                }}
              />
            )}
          />
          <View style={styles.modalActions}>
            <Pressable
              accessibilityRole="button"
              onPress={() => {
                setShowThreads(false);
                ignorePromise(props.newChat());
              }}
              style={styles.modalPrimaryButton}>
              <Text style={styles.sendButtonText}>New Chat</Text>
            </Pressable>
            <Pressable
              accessibilityRole="button"
              onPress={() => {
                setShowThreads(false);
                ignorePromise(props.logout());
              }}
              style={styles.modalSecondaryButton}>
              <Text style={styles.modalSecondaryText}>Log Out</Text>
            </Pressable>
          </View>
        </View>
      </Modal>
    </KeyboardAvoidingView>
  );
}

const styles = StyleSheet.create({
  container: {
    backgroundColor: '#f8f7f3',
    flex: 1,
  },
  containerDark: {
    backgroundColor: '#101418',
  },
  header: {
    alignItems: 'center',
    backgroundColor: '#fbfaf7',
    borderBottomColor: '#dfddd5',
    borderBottomWidth: StyleSheet.hairlineWidth,
    flexDirection: 'row',
    gap: 10,
    paddingHorizontal: 12,
    paddingVertical: 10,
  },
  headerDark: {
    backgroundColor: '#151b20',
    borderBottomColor: '#283138',
  },
  headerButton: {
    borderRadius: 8,
    paddingHorizontal: 10,
    paddingVertical: 8,
  },
  headerButtonText: {
    color: '#23332d',
    fontSize: 15,
    fontWeight: '700',
  },
  headerTitleWrap: {
    flex: 1,
    minWidth: 0,
  },
  headerTitle: {
    color: '#17211c',
    fontSize: 17,
    fontWeight: '800',
    letterSpacing: 0,
    textAlign: 'center',
  },
  modelText: {
    color: '#6a746f',
    fontSize: 12,
    marginTop: 2,
    textAlign: 'center',
  },
  textDark: {
    color: '#eef4f1',
  },
  errorBar: {
    alignItems: 'center',
    backgroundColor: '#b42318',
    flexDirection: 'row',
    gap: 10,
    paddingHorizontal: 12,
    paddingVertical: 10,
  },
  errorText: {
    color: '#fff',
    flex: 1,
    fontSize: 13,
    lineHeight: 18,
  },
  errorButton: {
    borderColor: 'rgba(255,255,255,0.55)',
    borderRadius: 8,
    borderWidth: 1,
    paddingHorizontal: 8,
    paddingVertical: 5,
  },
  errorButtonText: {
    color: '#fff',
    fontSize: 12,
    fontWeight: '700',
  },
  loadingOverlay: {
    alignItems: 'center',
    height: 36,
    justifyContent: 'center',
  },
  messageList: {
    flexGrow: 1,
    gap: 12,
    padding: 14,
  },
  emptyState: {
    alignItems: 'center',
    flex: 1,
    justifyContent: 'center',
    minHeight: 260,
  },
  emptyTitle: {
    color: '#5c6861',
    fontSize: 17,
    fontWeight: '700',
  },
  messageRow: {
    flexDirection: 'row',
  },
  messageRowUser: {
    justifyContent: 'flex-end',
  },
  messageRowAssistant: {
    justifyContent: 'flex-start',
  },
  messageBubble: {
    borderRadius: 8,
    maxWidth: '86%',
    paddingHorizontal: 12,
    paddingVertical: 10,
  },
  userBubble: {
    backgroundColor: '#0d6b5f',
  },
  assistantBubble: {
    backgroundColor: '#fff',
    borderColor: '#e4e1d9',
    borderWidth: StyleSheet.hairlineWidth,
  },
  assistantBubbleDark: {
    backgroundColor: '#1b2329',
    borderColor: '#2f3940',
  },
  userMessageText: {
    color: '#fff',
    fontSize: 16,
    lineHeight: 22,
  },
  markdownBody: {
    color: '#17211c',
    fontSize: 16,
    lineHeight: 22,
  },
  markdownBodyDark: {
    color: '#eef4f1',
    fontSize: 16,
    lineHeight: 22,
  },
  markdownParagraph: {
    marginBottom: 0,
    marginTop: 0,
  },
  composer: {
    alignItems: 'flex-end',
    backgroundColor: '#fbfaf7',
    borderTopColor: '#dfddd5',
    borderTopWidth: StyleSheet.hairlineWidth,
    flexDirection: 'row',
    gap: 10,
    padding: 12,
  },
  composerDark: {
    backgroundColor: '#151b20',
    borderTopColor: '#283138',
  },
  input: {
    backgroundColor: '#fff',
    borderColor: '#d4d1c9',
    borderRadius: 8,
    borderWidth: 1,
    color: '#17211c',
    flex: 1,
    fontSize: 16,
    maxHeight: 132,
    minHeight: 44,
    paddingHorizontal: 12,
    paddingVertical: 10,
  },
  inputDark: {
    backgroundColor: '#101418',
    borderColor: '#354047',
    color: '#eef4f1',
  },
  sendButton: {
    alignItems: 'center',
    backgroundColor: '#0d6b5f',
    borderRadius: 8,
    justifyContent: 'center',
    minHeight: 44,
    minWidth: 72,
    paddingHorizontal: 14,
  },
  sendButtonDisabled: {
    opacity: 0.42,
  },
  cancelButton: {
    backgroundColor: '#9c2f24',
  },
  sendButtonText: {
    color: '#fff',
    fontSize: 15,
    fontWeight: '800',
  },
  modal: {
    backgroundColor: '#f8f7f3',
    flex: 1,
    paddingTop: 44,
  },
  modalHeader: {
    alignItems: 'center',
    flexDirection: 'row',
    justifyContent: 'space-between',
    paddingHorizontal: 16,
    paddingVertical: 12,
  },
  modalTitle: {
    color: '#17211c',
    fontSize: 28,
    fontWeight: '800',
    letterSpacing: 0,
  },
  threadRow: {
    alignItems: 'center',
    borderBottomColor: '#e2dfd6',
    borderBottomWidth: StyleSheet.hairlineWidth,
    flexDirection: 'row',
    gap: 10,
    paddingHorizontal: 16,
    paddingVertical: 14,
  },
  threadRowSelected: {
    backgroundColor: '#e8f2ef',
  },
  threadText: {
    flex: 1,
    minWidth: 0,
  },
  threadTitle: {
    color: '#17211c',
    fontSize: 16,
    fontWeight: '700',
  },
  threadMeta: {
    color: '#68736d',
    fontSize: 12,
    marginTop: 3,
  },
  threadSelectedMark: {
    color: '#0d6b5f',
    fontSize: 12,
    fontWeight: '800',
  },
  emptyListText: {
    color: '#5c6861',
    padding: 18,
  },
  modalActions: {
    borderTopColor: '#e2dfd6',
    borderTopWidth: StyleSheet.hairlineWidth,
    gap: 10,
    padding: 16,
  },
  modalPrimaryButton: {
    alignItems: 'center',
    backgroundColor: '#0d6b5f',
    borderRadius: 8,
    minHeight: 48,
    justifyContent: 'center',
  },
  modalSecondaryButton: {
    alignItems: 'center',
    borderColor: '#cfcac0',
    borderRadius: 8,
    borderWidth: 1,
    minHeight: 48,
    justifyContent: 'center',
  },
  modalSecondaryText: {
    color: '#8f2b22',
    fontSize: 15,
    fontWeight: '800',
  },
});
