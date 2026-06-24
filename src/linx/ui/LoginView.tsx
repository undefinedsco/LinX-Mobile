import React, { useState } from 'react';
import {
  ActivityIndicator,
  Pressable,
  StyleSheet,
  Text,
  TextInput,
  useColorScheme,
  View,
} from 'react-native';
import { LINX_CONTRACT } from '../contract';
import type { LinxLoginOptions } from '../storageSettings';
import { LinxPalette, linxColors } from './LinxPalette';

interface LoginViewProps {
  isBusy: boolean;
  errorMessage?: string;
  onLogin: (options?: LinxLoginOptions) => void;
}

export function LoginView({ isBusy, errorMessage, onLogin }: LoginViewProps) {
  const isDark = useColorScheme() === 'dark';
  const colors = linxColors(isDark);
  const [showStorageSettings, setShowStorageSettings] = useState(false);
  const [useCustomStorage, setUseCustomStorage] = useState(false);
  const [customStorageUrl, setCustomStorageUrl] = useState('');
  const issuerUrl = `${LINX_CONTRACT.issuerOrigin}/`;
  const loginOptions: LinxLoginOptions | undefined = useCustomStorage
    ? { storageServerUrl: customStorageUrl }
    : undefined;

  return (
    <View style={[styles.container, { backgroundColor: colors.background }]}>
      <View style={styles.mark}>
        <View style={styles.markCircle}>
          <Text style={styles.markText}>L</Text>
        </View>
      </View>
      <View style={styles.content}>
        <Text style={[styles.title, { color: colors.text }]}>LinX</Text>
        <Text style={[styles.subtitle, { color: colors.secondaryText }]}>
          OpenAI-compatible LinX cloud runtime with Solid Pod chat memory.
        </Text>
        <View
          style={[
            styles.featurePill,
            { backgroundColor: colors.surface, borderColor: colors.border },
          ]}>
          <Text style={[styles.featureText, { color: colors.secondaryText }]}>
            Secure OIDC login
          </Text>
          <Text style={[styles.featureText, { color: colors.secondaryText }]}>
            Pod-backed history
          </Text>
        </View>
        <Pressable
          accessibilityRole="button"
          disabled={isBusy}
          onPress={() => setShowStorageSettings(current => !current)}
          style={({ pressed }) => [
            styles.settingsToggle,
            { borderColor: colors.border },
            pressed && styles.settingsTogglePressed,
            isBusy && styles.buttonDisabled,
          ]}
          testID="storage-settings-toggle">
          <Text style={[styles.settingsToggleText, { color: colors.secondaryText }]}>
            {showStorageSettings ? 'Hide storage settings' : 'Storage settings'}
          </Text>
        </Pressable>
        {showStorageSettings ? (
          <View
            style={[
              styles.storagePanel,
              { backgroundColor: colors.surface, borderColor: colors.border },
            ]}>
            <Text style={[styles.storageLabel, { color: colors.secondaryText }]}>Provider / IDP</Text>
            <Text style={[styles.storageValue, { color: colors.text }]}>{issuerUrl}</Text>
            <Text style={[styles.storageHelp, { color: colors.secondaryText }]}>Storage server</Text>
            <Pressable
              accessibilityRole="radio"
              accessibilityState={{ checked: !useCustomStorage }}
              onPress={() => setUseCustomStorage(false)}
              style={[
                styles.storageOption,
                !useCustomStorage && styles.storageOptionSelected,
                { borderColor: colors.border },
              ]}
              testID="storage-auto-option">
              <Text style={[styles.storageOptionText, { color: colors.text }]}>Auto discover from WebID</Text>
            </Pressable>
            <Pressable
              accessibilityRole="radio"
              accessibilityState={{ checked: useCustomStorage }}
              onPress={() => setUseCustomStorage(true)}
              style={[
                styles.storageOption,
                useCustomStorage && styles.storageOptionSelected,
                { borderColor: colors.border },
              ]}
              testID="storage-custom-option">
              <Text style={[styles.storageOptionText, { color: colors.text }]}>Custom SP URL</Text>
            </Pressable>
            {useCustomStorage ? (
              <TextInput
                autoCapitalize="none"
                autoCorrect={false}
                editable={!isBusy}
                keyboardType="url"
                onChangeText={setCustomStorageUrl}
                placeholder="https://node-0000.undefineds.co/"
                placeholderTextColor={colors.secondaryText}
                style={[
                  styles.storageInput,
                  {
                    borderColor: colors.border,
                    color: colors.text,
                  },
                ]}
                testID="custom-sp-url-input"
                value={customStorageUrl}
              />
            ) : null}
          </View>
        ) : null}
        {errorMessage ? (
          <Text accessibilityRole="alert" style={styles.error}>
            {errorMessage}
          </Text>
        ) : null}
        <Pressable
          accessibilityRole="button"
          disabled={isBusy}
          onPress={() => onLogin(loginOptions)}
          style={({ pressed }) => [
            styles.button,
            pressed && styles.buttonPressed,
            isBusy && styles.buttonDisabled,
          ]}
          testID="login-button">
          {isBusy ? <ActivityIndicator color="#fff" /> : null}
          <Text style={styles.buttonText}>
            {isBusy ? 'Connecting...' : 'Continue with LinX Cloud'}
          </Text>
        </Pressable>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    justifyContent: 'center',
    padding: 24,
  },
  mark: {
    alignItems: 'flex-start',
    marginBottom: 22,
  },
  markCircle: {
    alignItems: 'center',
    backgroundColor: LinxPalette.accent,
    borderRadius: 23,
    height: 46,
    justifyContent: 'center',
    width: 46,
  },
  markText: {
    color: '#fff',
    fontSize: 22,
    fontWeight: '900',
  },
  content: {
    gap: 18,
  },
  title: {
    fontSize: 54,
    fontWeight: '900',
    letterSpacing: 0,
    lineHeight: 60,
  },
  subtitle: {
    fontSize: 18,
    fontWeight: '600',
    lineHeight: 25,
    maxWidth: 360,
  },
  featurePill: {
    alignSelf: 'flex-start',
    borderRadius: 14,
    borderWidth: 1,
    gap: 6,
    paddingHorizontal: 14,
    paddingVertical: 12,
  },
  featureText: {
    fontSize: 14,
    fontWeight: '700',
  },
  settingsToggle: {
    alignSelf: 'flex-start',
    borderRadius: 12,
    borderWidth: 1,
    paddingHorizontal: 14,
    paddingVertical: 10,
  },
  settingsTogglePressed: {
    opacity: 0.72,
  },
  settingsToggleText: {
    fontSize: 14,
    fontWeight: '800',
  },
  storagePanel: {
    borderRadius: 16,
    borderWidth: 1,
    gap: 10,
    padding: 14,
  },
  storageLabel: {
    fontSize: 12,
    fontWeight: '800',
    textTransform: 'uppercase',
  },
  storageValue: {
    fontSize: 14,
    fontWeight: '700',
  },
  storageHelp: {
    fontSize: 12,
    fontWeight: '700',
    marginTop: 4,
  },
  storageOption: {
    borderRadius: 10,
    borderWidth: 1,
    paddingHorizontal: 12,
    paddingVertical: 10,
  },
  storageOptionSelected: {
    backgroundColor: 'rgba(13, 107, 95, 0.08)',
  },
  storageOptionText: {
    fontSize: 14,
    fontWeight: '800',
  },
  storageInput: {
    borderRadius: 10,
    borderWidth: 1,
    fontSize: 14,
    fontWeight: '700',
    minHeight: 44,
    paddingHorizontal: 12,
    paddingVertical: 10,
  },
  error: {
    color: LinxPalette.warning,
    fontSize: 14,
    fontWeight: '700',
    lineHeight: 20,
  },
  button: {
    alignItems: 'center',
    backgroundColor: LinxPalette.accent,
    borderRadius: 14,
    flexDirection: 'row',
    gap: 10,
    justifyContent: 'center',
    minHeight: 54,
    paddingHorizontal: 18,
  },
  buttonPressed: {
    backgroundColor: LinxPalette.accentPressed,
  },
  buttonDisabled: {
    opacity: 0.72,
  },
  buttonText: {
    color: '#fff',
    fontSize: 16,
    fontWeight: '800',
  },
});
