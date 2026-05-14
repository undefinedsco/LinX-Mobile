import React from 'react';
import {
  ActivityIndicator,
  Pressable,
  StyleSheet,
  Text,
  useColorScheme,
  View,
} from 'react-native';

interface LoginViewProps {
  isBusy: boolean;
  errorMessage?: string;
  onLogin: () => void;
}

export function LoginView({ isBusy, errorMessage, onLogin }: LoginViewProps) {
  const isDark = useColorScheme() === 'dark';
  return (
    <View style={[styles.container, isDark && styles.containerDark]}>
      <View style={styles.content}>
        <Text style={[styles.title, isDark && styles.titleDark]}>LinX</Text>
        <Text style={[styles.subtitle, isDark && styles.subtitleDark]}>
          Sign in to continue your mobile chats.
        </Text>
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
    backgroundColor: '#f6f4ee',
    justifyContent: 'center',
    padding: 24,
  },
  containerDark: {
    backgroundColor: '#101418',
  },
  content: {
    gap: 18,
  },
  title: {
    color: '#17211c',
    fontSize: 52,
    fontWeight: '800',
    letterSpacing: 0,
  },
  titleDark: {
    color: '#f7faf8',
  },
  subtitle: {
    color: '#59645f',
    fontSize: 18,
    lineHeight: 25,
  },
  subtitleDark: {
    color: '#bdc7c2',
  },
  error: {
    color: '#b42318',
    fontSize: 14,
    lineHeight: 20,
  },
  button: {
    alignItems: 'center',
    backgroundColor: '#0d6b5f',
    borderRadius: 8,
    flexDirection: 'row',
    gap: 10,
    justifyContent: 'center',
    minHeight: 54,
    paddingHorizontal: 18,
  },
  buttonPressed: {
    opacity: 0.88,
  },
  buttonDisabled: {
    opacity: 0.72,
  },
  buttonText: {
    color: '#fff',
    fontSize: 16,
    fontWeight: '700',
  },
});
