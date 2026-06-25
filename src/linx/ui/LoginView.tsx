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
  const [storageMode, setStorageMode] = useState<'auto' | 'custom'>('auto');
  const [customSpServerUrl, setCustomSpServerUrl] = useState('');

  const submitLogin = () => {
    onLogin(
      storageMode === 'custom'
        ? { storageServerUrl: customSpServerUrl.trim() }
        : undefined,
    );
  };

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
        {errorMessage ? (
          <Text accessibilityRole="alert" style={styles.error}>
            {errorMessage}
          </Text>
        ) : null}
        <Pressable
          accessibilityRole="button"
          testID="storage-settings-toggle"
          disabled={isBusy}
          onPress={() => setShowStorageSettings(current => !current)}
          style={({ pressed }) => [
            styles.settingsToggle,
            { borderColor: colors.border, backgroundColor: colors.surface },
            pressed && styles.settingsTogglePressed,
            isBusy && styles.buttonDisabled,
          ]}>
          <Text style={[styles.settingsToggleText, { color: colors.text }]}>⚙ Storage settings</Text>
        </Pressable>
        {showStorageSettings ? (
          <View style={[styles.settingsPanel, { borderColor: colors.border, backgroundColor: colors.surface }]}>
            <Text style={[styles.settingsLabel, { color: colors.text }]}>Provider / IDP</Text>
            <Text style={[styles.settingsValue, { color: colors.secondaryText }]}>{`${LINX_CONTRACT.issuerOrigin}/`}</Text>
            <Text style={[styles.settingsLabel, { color: colors.text }]}>Storage / SP</Text>
            <Pressable
              accessibilityRole="radio"
              accessibilityState={{ selected: storageMode === 'auto' }}
              testID="storage-auto-option"
              disabled={isBusy}
              onPress={() => setStorageMode('auto')}
              style={styles.radioRow}>
              <Text style={[styles.radioText, { color: colors.secondaryText }]}>Auto discover from WebID</Text>
            </Pressable>
            <Pressable
              accessibilityRole="radio"
              accessibilityState={{ selected: storageMode === 'custom' }}
              testID="storage-custom-option"
              disabled={isBusy}
              onPress={() => setStorageMode('custom')}
              style={styles.radioRow}>
              <Text style={[styles.radioText, { color: colors.secondaryText }]}>Custom SP URL</Text>
            </Pressable>
            {storageMode === 'custom' ? (
              <>
                <TextInput
                  autoCapitalize="none"
                  autoCorrect={false}
                  editable={!isBusy}
                  keyboardType="url"
                  onChangeText={setCustomSpServerUrl}
                  placeholder="https://node-0000.undefineds.co/"
                  placeholderTextColor={colors.tertiaryText}
                  style={[
                    styles.input,
                    {
                      backgroundColor: colors.input,
                      borderColor: colors.border,
                      color: colors.text,
                    },
                  ]}
                  testID="custom-sp-url-input"
                  value={customSpServerUrl}
                />
                <Text style={[styles.helperText, { color: colors.tertiaryText }]}>
                  Enter the SP server root only. The pod path is derived after cloud login from your WebID.
                </Text>
              </>
            ) : null}
          </View>
        ) : null}
        <Pressable
          accessibilityRole="button"
          testID="login-button"
          disabled={isBusy}
          onPress={submitLogin}
          style={({ pressed }) => [
            styles.button,
            pressed && styles.buttonPressed,
            isBusy && styles.buttonDisabled,
          ]}>
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
  error: {
    color: LinxPalette.warning,
    fontSize: 14,
    fontWeight: '700',
    lineHeight: 20,
  },
  settingsToggle: {
    alignItems: 'center',
    alignSelf: 'flex-start',
    borderRadius: 12,
    borderWidth: 1,
    minHeight: 40,
    paddingHorizontal: 14,
    justifyContent: 'center',
  },
  settingsTogglePressed: {
    opacity: 0.86,
  },
  settingsToggleText: {
    fontSize: 14,
    fontWeight: '800',
  },
  settingsPanel: {
    borderRadius: 14,
    borderWidth: 1,
    gap: 10,
    padding: 14,
  },
  settingsLabel: {
    fontSize: 13,
    fontWeight: '900',
  },
  settingsValue: {
    fontSize: 13,
    fontWeight: '700',
  },
  radioRow: {
    minHeight: 32,
    justifyContent: 'center',
  },
  radioText: {
    fontSize: 14,
    fontWeight: '700',
  },
  helperText: {
    fontSize: 12,
    fontWeight: '600',
    lineHeight: 17,
  },
  input: {
    borderRadius: 10,
    borderWidth: 1,
    minHeight: 44,
    paddingHorizontal: 12,
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
