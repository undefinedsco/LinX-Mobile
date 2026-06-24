import React, { useEffect, useState } from 'react';
import {
  Linking,
  Pressable,
  StyleSheet,
  Text,
  View,
} from 'react-native';
import { LinxPalette } from '../ui/LinxPalette';
import {
  fetchAvailableUpdate,
  type LinxAvailableUpdate,
} from './updateManifest';

export function UpdatePrompt({
  manifestUrl,
}: {
  manifestUrl?: string | null;
}) {
  const [update, setUpdate] = useState<LinxAvailableUpdate | null>(null);
  const [dismissedBuild, setDismissedBuild] = useState<number | null>(null);

  useEffect(() => {
    let cancelled = false;
    fetchAvailableUpdate({ manifestUrl })
      .then(next => {
        if (!cancelled) {
          setUpdate(next);
        }
      })
      .catch(() => {
        if (!cancelled) {
          setUpdate(null);
        }
      });
    return () => {
      cancelled = true;
    };
  }, [manifestUrl]);

  if (!update || dismissedBuild === update.latestBuild) {
    return null;
  }

  const openDownload = () => {
    Linking.openURL(update.downloadUrl).catch(() => undefined);
  };

  return (
    <View style={styles.banner} testID="update-prompt">
      <View style={styles.copy}>
        <Text style={styles.title}>New LinX Mobile version available</Text>
        <Text style={styles.body}>
          {`Version ${update.latestVersion} (${update.latestBuild}) is ready${update.required ? ' and required' : ''}.`}
        </Text>
        {update.releaseNotes ? (
          <Text style={styles.notes}>{update.releaseNotes}</Text>
        ) : null}
      </View>
      <View style={styles.actions}>
        {!update.required ? (
          <Pressable
            accessibilityRole="button"
            onPress={() => setDismissedBuild(update.latestBuild)}
            style={styles.secondaryButton}>
            <Text style={styles.secondaryText}>Later</Text>
          </Pressable>
        ) : null}
        <Pressable
          accessibilityRole="link"
          onPress={openDownload}
          style={styles.primaryButton}>
          <Text style={styles.primaryText}>Download</Text>
        </Pressable>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  banner: {
    backgroundColor: '#fff8e6',
    borderBottomColor: '#f2cf78',
    borderBottomWidth: 1,
    gap: 10,
    paddingHorizontal: 14,
    paddingVertical: 12,
  },
  copy: {
    gap: 4,
  },
  title: {
    color: '#4f3910',
    fontSize: 14,
    fontWeight: '900',
  },
  body: {
    color: '#624719',
    fontSize: 12,
    lineHeight: 17,
  },
  notes: {
    color: '#6f531f',
    fontSize: 12,
    lineHeight: 17,
  },
  actions: {
    flexDirection: 'row',
    gap: 10,
  },
  primaryButton: {
    alignItems: 'center',
    backgroundColor: LinxPalette.accent,
    borderRadius: 10,
    minHeight: 36,
    justifyContent: 'center',
    paddingHorizontal: 14,
  },
  primaryText: {
    color: '#fff',
    fontSize: 13,
    fontWeight: '900',
  },
  secondaryButton: {
    alignItems: 'center',
    borderColor: LinxPalette.accent,
    borderRadius: 10,
    borderWidth: 1,
    minHeight: 36,
    justifyContent: 'center',
    paddingHorizontal: 14,
  },
  secondaryText: {
    color: LinxPalette.accent,
    fontSize: 13,
    fontWeight: '900',
  },
});
