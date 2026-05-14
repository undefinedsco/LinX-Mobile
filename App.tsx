import React from 'react';
import {
  ActivityIndicator,
  StatusBar,
  StyleSheet,
  Text,
  useColorScheme,
  View,
} from 'react-native';
import {
  SafeAreaProvider,
  SafeAreaView,
} from 'react-native-safe-area-context';
import { useLinxChatApp } from './src/linx/chat/useLinxChatApp';
import { ChatScreen } from './src/linx/ui/ChatScreen';
import { LoginView } from './src/linx/ui/LoginView';

function App() {
  const isDarkMode = useColorScheme() === 'dark';

  return (
    <SafeAreaProvider>
      <StatusBar barStyle={isDarkMode ? 'light-content' : 'dark-content'} />
      <SafeAreaView style={styles.safeArea}>
        <AppContent />
      </SafeAreaView>
    </SafeAreaProvider>
  );
}

function AppContent() {
  const app = useLinxChatApp();

  if (app.phase === 'restoring') {
    return (
      <View style={styles.center}>
        <ActivityIndicator />
      </View>
    );
  }

  if (app.phase === 'unauthenticated' || app.phase === 'authenticating') {
    return (
      <LoginView
        errorMessage={app.errorMessage}
        isBusy={app.phase === 'authenticating'}
        onLogin={() => {
          app.login().catch(() => undefined);
        }}
      />
    );
  }

  if (app.phase === 'error' && !app.session) {
    return (
      <View style={styles.errorScreen}>
        <Text accessibilityRole="alert" style={styles.errorText}>
          {app.errorMessage ?? 'LinX failed to start.'}
        </Text>
        <Text
          onPress={() => {
            app.retry().catch(() => undefined);
          }}
          style={styles.retryText}>
          Retry
        </Text>
      </View>
    );
  }

  return <ChatScreen {...app} />;
}

const styles = StyleSheet.create({
  safeArea: {
    flex: 1,
  },
  center: {
    alignItems: 'center',
    flex: 1,
    justifyContent: 'center',
  },
  errorScreen: {
    alignItems: 'center',
    flex: 1,
    gap: 16,
    justifyContent: 'center',
    padding: 24,
  },
  errorText: {
    color: '#b42318',
    fontSize: 15,
    lineHeight: 21,
    textAlign: 'center',
  },
  retryText: {
    color: '#0d6b5f',
    fontSize: 16,
    fontWeight: '800',
  },
});

export default App;
