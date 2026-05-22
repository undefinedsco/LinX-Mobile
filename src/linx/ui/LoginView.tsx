import React from 'react';
import {
  ActivityIndicator,
  Pressable,
  StyleSheet,
  Text,
  useColorScheme,
  View,
} from 'react-native';
import { LinxPalette, linxColors } from './LinxPalette';

interface LoginViewProps {
  isBusy: boolean;
  errorMessage?: string;
  onLogin: () => void;
}

export function LoginView({ isBusy, errorMessage, onLogin }: LoginViewProps) {
  const isDark = useColorScheme() === 'dark';
  const colors = linxColors(isDark);

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
          disabled={isBusy}
          onPress={onLogin}
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
