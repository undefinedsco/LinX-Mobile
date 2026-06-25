import React from 'react';
import {
  FlatList,
  Modal,
  Pressable,
  StyleSheet,
  Text,
  View,
} from 'react-native';
import type { LinxThreadSummary } from '../types';
import { LinxPalette, linxColors } from './LinxPalette';

interface ThreadListSheetProps {
  visible: boolean;
  isDark: boolean;
  threads: LinxThreadSummary[];
  selectedThreadId?: string;
  onClose: () => void;
  onSelectThread: (thread: LinxThreadSummary) => void;
  onNewChat: () => void;
  onOpenP2PSmoke: () => void;
  onLogout: () => void;
}

function formatThreadDate(value: string): string {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) {
    return '';
  }
  return date.toLocaleString(undefined, {
    month: 'short',
    day: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
  });
}

function ThreadRow({
  thread,
  selected,
  isDark,
  onPress,
}: {
  thread: LinxThreadSummary;
  selected: boolean;
  isDark: boolean;
  onPress: () => void;
}) {
  const colors = linxColors(isDark);
  return (
    <Pressable
      accessibilityRole="button"
      onPress={onPress}
      style={[
        styles.threadRow,
        { borderBottomColor: colors.border },
        selected && { backgroundColor: colors.selected },
      ]}>
      <View
        style={[
          styles.threadMark,
          { backgroundColor: selected ? LinxPalette.accent : colors.elevatedSurface },
        ]}>
        <Text
          style={[
            styles.threadMarkText,
            selected
              ? styles.threadMarkTextSelected
              : styles.threadMarkTextDefault,
          ]}>
          {selected ? 'OK' : 'AI'}
        </Text>
      </View>
      <View style={styles.threadText}>
        <Text numberOfLines={2} style={[styles.threadTitle, { color: colors.text }]}>
          {thread.title}
        </Text>
        <Text
          numberOfLines={1}
          style={[styles.threadMeta, { color: colors.secondaryText }]}>
          {formatThreadDate(thread.updatedAt)}
        </Text>
      </View>
      <Text style={[styles.threadChevron, { color: colors.tertiaryText }]}>
        {'>'}
      </Text>
    </Pressable>
  );
}

export function ThreadListSheet({
  visible,
  isDark,
  threads,
  selectedThreadId,
  onClose,
  onSelectThread,
  onNewChat,
  onOpenP2PSmoke,
  onLogout,
}: ThreadListSheetProps) {
  const colors = linxColors(isDark);

  return (
    <Modal animationType="slide" onRequestClose={onClose} visible={visible}>
      <View style={[styles.modal, { backgroundColor: colors.background }]}>
        <View
          style={[
            styles.modalHeader,
            {
              backgroundColor: colors.backgroundAlt,
              borderBottomColor: colors.border,
            },
          ]}>
          <Pressable
            accessibilityRole="button"
            onPress={onLogout}
            style={styles.iconButton}>
            <Text style={[styles.logoutText, { color: LinxPalette.warning }]}>
              Logout
            </Text>
          </Pressable>
          <Text style={[styles.modalTitle, { color: colors.text }]}>Chats</Text>
          <Pressable
            accessibilityRole="button"
            onPress={onClose}
            style={styles.iconButton}>
            <Text style={[styles.doneText, { color: LinxPalette.accent }]}>
              Done
            </Text>
          </Pressable>
        </View>

        <View style={styles.newChatWrap}>
          <Pressable
            accessibilityRole="button"
            onPress={onNewChat}
            style={({ pressed }) => [
              styles.newChatButton,
              { backgroundColor: colors.surface, borderColor: colors.border },
              pressed && styles.pressed,
            ]}>
            <Text style={[styles.newChatText, { color: LinxPalette.accent }]}>
              New chat
            </Text>
          </Pressable>
          <Pressable
            accessibilityRole="button"
            onPress={onOpenP2PSmoke}
            style={({ pressed }) => [
              styles.newChatButton,
              { backgroundColor: colors.surface, borderColor: colors.border },
              pressed && styles.pressed,
            ]}
            testID="open-p2p-smoke-button">
            <Text style={[styles.newChatText, { color: LinxPalette.accent }]}>
              P2P Smoke
            </Text>
          </Pressable>
        </View>

        <FlatList
          contentContainerStyle={threads.length === 0 && styles.emptyList}
          data={threads}
          keyExtractor={item => item.id}
          ListEmptyComponent={
            <View style={styles.emptyState}>
              <Text style={[styles.emptyTitle, { color: colors.text }]}>
                No chats yet
              </Text>
              <Text
                style={[styles.emptyDescription, { color: colors.secondaryText }]}>
                Start a new LinX conversation.
              </Text>
            </View>
          }
          renderItem={({ item }) => (
            <ThreadRow
              isDark={isDark}
              onPress={() => onSelectThread(item)}
              selected={item.id === selectedThreadId}
              thread={item}
            />
          )}
        />
      </View>
    </Modal>
  );
}

const styles = StyleSheet.create({
  modal: {
    flex: 1,
  },
  modalHeader: {
    alignItems: 'center',
    borderBottomWidth: StyleSheet.hairlineWidth,
    flexDirection: 'row',
    justifyContent: 'space-between',
    paddingHorizontal: 14,
    paddingTop: 52,
    paddingBottom: 12,
  },
  iconButton: {
    minWidth: 70,
    paddingVertical: 8,
  },
  logoutText: {
    fontSize: 15,
    fontWeight: '700',
  },
  doneText: {
    fontSize: 15,
    fontWeight: '800',
    textAlign: 'right',
  },
  modalTitle: {
    fontSize: 17,
    fontWeight: '800',
    letterSpacing: 0,
  },
  newChatWrap: {
    gap: 10,
    paddingHorizontal: 16,
    paddingVertical: 12,
  },
  newChatButton: {
    alignItems: 'center',
    borderRadius: 12,
    borderWidth: 1,
    minHeight: 48,
    justifyContent: 'center',
  },
  pressed: {
    opacity: 0.82,
  },
  newChatText: {
    fontSize: 16,
    fontWeight: '800',
  },
  emptyList: {
    flexGrow: 1,
  },
  emptyState: {
    alignItems: 'center',
    flex: 1,
    justifyContent: 'center',
    padding: 32,
  },
  emptyTitle: {
    fontSize: 18,
    fontWeight: '800',
    marginBottom: 6,
  },
  emptyDescription: {
    fontSize: 14,
    lineHeight: 20,
    textAlign: 'center',
  },
  threadRow: {
    alignItems: 'center',
    borderBottomWidth: StyleSheet.hairlineWidth,
    flexDirection: 'row',
    gap: 12,
    minHeight: 72,
    paddingHorizontal: 16,
    paddingVertical: 10,
  },
  threadMark: {
    alignItems: 'center',
    borderRadius: 18,
    height: 36,
    justifyContent: 'center',
    width: 36,
  },
  threadMarkText: {
    fontWeight: '900',
    fontSize: 11,
  },
  threadMarkTextSelected: {
    color: '#fff',
  },
  threadMarkTextDefault: {
    color: LinxPalette.blue,
  },
  threadText: {
    flex: 1,
    minWidth: 0,
  },
  threadTitle: {
    fontSize: 16,
    fontWeight: '800',
    lineHeight: 20,
  },
  threadMeta: {
    fontSize: 12,
    fontWeight: '600',
    marginTop: 5,
  },
  threadChevron: {
    fontSize: 18,
    fontWeight: '700',
  },
});
