import React from 'react';
import { StatusBar, StyleSheet } from 'react-native';
import { SafeAreaProvider, SafeAreaView } from 'react-native-safe-area-context';
import { UpdatePrompt } from '../linx/update/UpdatePrompt';
import { P2PSmokeScreen, type P2PSmokeDefaults } from './P2PSmokeScreen';

export default function P2PSmokeApp({
  p2pSmokeDefaults,
  updateManifestUrl,
}: {
  p2pSmokeDefaults?: P2PSmokeDefaults;
  updateManifestUrl?: string;
}) {
  return (
    <SafeAreaProvider>
      <StatusBar barStyle="dark-content" />
      <SafeAreaView style={styles.safeArea}>
        <UpdatePrompt manifestUrl={updateManifestUrl ?? p2pSmokeDefaults?.updateManifestUrl} />
        <P2PSmokeScreen initialSmokeDefaults={p2pSmokeDefaults} />
      </SafeAreaView>
    </SafeAreaProvider>
  );
}


const styles = StyleSheet.create({
  safeArea: {
    flex: 1,
  },
});
