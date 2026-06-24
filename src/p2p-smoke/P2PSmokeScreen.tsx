import React, { useState } from 'react';
import {
  ActivityIndicator,
  Pressable,
  ScrollView,
  Share,
  StyleSheet,
  Text,
  TextInput,
  View,
} from 'react-native';
import type { LinxAuthSession } from '../linx/types';
import { deriveP2PSmokeDefaultsFromLocalStorageUrl } from './deriveP2PSmokeTarget';
import {
  createP2PSmokeAuthController,
  formatP2PSmokeEvidenceForShare,
  runP2PSmoke,
  type P2PSmokeEvidence,
} from './mobileP2PSmoke';

const DEFAULT_IDP = 'https://id.undefineds.co/';
const DEFAULT_SP = 'https://node-0000.undefineds.co/alice/';
const DEFAULT_RESOURCE_PATH = '.data/linx-mobile-p2p-smoke.txt';
const DEFAULT_CLIENT_ID = `phone-${Math.floor(Date.now() / 1000)}`;

export interface P2PSmokeDefaults {
  idpUrl?: string;
  storageUrl?: string;
  clientId?: string;
  resourcePath?: string;
  localSpUrl?: string;
  apiBaseUrl?: string;
  nodeId?: string;
  updateManifestUrl?: string;
}

export function P2PSmokeScreen({
  initialSmokeDefaults,
}: {
  initialSmokeDefaults?: P2PSmokeDefaults;
}) {
  const [idpUrl, setIdpUrl] = useState(initialSmokeDefaults?.idpUrl ?? DEFAULT_IDP);
  const [storageUrl, setStorageUrl] = useState(initialSmokeDefaults?.storageUrl ?? DEFAULT_SP);
  const [resourcePath, setResourcePath] = useState(initialSmokeDefaults?.resourcePath ?? DEFAULT_RESOURCE_PATH);
  const [localSpUrl, setLocalSpUrl] = useState(initialSmokeDefaults?.localSpUrl ?? initialSmokeDefaults?.storageUrl ?? DEFAULT_SP);
  const [apiBaseUrl, setApiBaseUrl] = useState(initialSmokeDefaults?.apiBaseUrl ?? '');
  const [nodeId, setNodeId] = useState(initialSmokeDefaults?.nodeId ?? '');
  const [clientId, setClientId] = useState(initialSmokeDefaults?.clientId ?? DEFAULT_CLIENT_ID);
  const [isRunning, setIsRunning] = useState(false);
  const [isLoggingIn, setIsLoggingIn] = useState(false);
  const [session, setSession] = useState<LinxAuthSession | null>(null);
  const [result, setResult] = useState<P2PSmokeEvidence | null>(null);
  const [error, setError] = useState<string | null>(null);

  const applyLocalSpUrl = () => {
    setError(null);
    try {
      const derived = deriveP2PSmokeDefaultsFromLocalStorageUrl(localSpUrl || storageUrl);
      setIdpUrl(derived.idpUrl);
      setStorageUrl(derived.storageUrl);
      setApiBaseUrl(derived.apiBaseUrl);
      setNodeId(derived.nodeId);
      setResourcePath(derived.resourcePath);
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : String(caught));
    }
  };

  const login = async () => {
    setIsLoggingIn(true);
    setError(null);
    try {
      setSession(await createP2PSmokeAuthController(idpUrl).login());
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : String(caught));
    } finally {
      setIsLoggingIn(false);
    }
  };

  const run = async () => {
    setIsRunning(true);
    setResult(null);
    setError(null);
    try {
      const evidence = await runP2PSmoke({
        idpUrl,
        storageUrl,
        resourcePath,
        apiBaseUrl: apiBaseUrl.trim() || undefined,
        nodeId: nodeId.trim() || undefined,
        clientId: clientId.trim() || DEFAULT_CLIENT_ID,
      });
      setResult(evidence);
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : String(caught));
    } finally {
      setIsRunning(false);
    }
  };

  const shareResult = async () => {
    if (!result) {
      return;
    }
    setError(null);
    try {
      await Share.share({
        title: 'LinX P2P Smoke client result',
        message: formatP2PSmokeEvidenceForShare(result),
      });
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : String(caught));
    }
  };

  return (
    <ScrollView contentContainerStyle={styles.container} keyboardShouldPersistTaps="handled">
      <Text style={styles.title}>LinX P2P Smoke</Text>
      <Text style={styles.description}>
        Standalone validation build. Product chat remains in the normal LinXMobile package.
      </Text>

      <Field
        label="Local SP URL"
        onChangeText={setLocalSpUrl}
        placeholder="https://node-0000.undefineds.co/alice/"
        value={localSpUrl}
      />
      <Pressable
        accessibilityRole="button"
        disabled={isLoggingIn || isRunning}
        onPress={applyLocalSpUrl}
        style={[styles.secondaryButton, (isLoggingIn || isRunning) && styles.buttonDisabled]}>
        <Text style={styles.secondaryButtonText}>Apply local SP</Text>
      </Pressable>
      <Field label="Cloud IDP provider" onChangeText={setIdpUrl} value={idpUrl} />
      <Field label="SP storage URL" onChangeText={setStorageUrl} value={storageUrl} />
      <Field label="Client ID" onChangeText={setClientId} value={clientId} />
      <Field label="Resource path" onChangeText={setResourcePath} value={resourcePath} />
      <View style={styles.derivedBox}>
        <Text selectable style={styles.derivedText}>{`apiBaseUrl: ${apiBaseUrl || '(derived from IDP)'}`}</Text>
        <Text selectable style={styles.derivedText}>{`nodeId: ${nodeId || '(derived from SP)'}`}</Text>
      </View>
      <Pressable
        accessibilityRole="button"
        disabled={isLoggingIn || isRunning}
        onPress={login}
        style={[styles.secondaryButton, (isLoggingIn || isRunning) && styles.buttonDisabled]}>
        {isLoggingIn ? <ActivityIndicator color="#0d7568" /> : null}
        <Text style={styles.secondaryButtonText}>
          {isLoggingIn ? 'Logging in...' : 'Login to IDP'}
        </Text>
      </Pressable>
      {session?.webId ? (
        <Text selectable style={styles.session}>
          {`Logged in: ${session.webId}`}
        </Text>
      ) : null}
      <Pressable
        accessibilityRole="button"
        disabled={isLoggingIn || isRunning}
        onPress={run}
        style={[styles.button, (isLoggingIn || isRunning) && styles.buttonDisabled]}>
        {isRunning ? <ActivityIndicator color="#fff" /> : null}
        <Text style={styles.buttonText}>{isRunning ? 'Running...' : 'Run P2P write/read smoke'}</Text>
      </Pressable>

      {error ? <Text style={styles.error}>{error}</Text> : null}
      {result ? (
        <>
          <Pressable
            accessibilityRole="button"
            onPress={shareResult}
            style={styles.secondaryButton}>
            <Text style={styles.secondaryButtonText}>Share result JSON</Text>
          </Pressable>
          <Text selectable style={styles.result}>
            {formatP2PSmokeEvidenceForShare(result)}
          </Text>
        </>
      ) : null}
    </ScrollView>
  );
}

function Field({
  label,
  value,
  onChangeText,
  placeholder,
}: {
  label: string;
  value: string;
  onChangeText: (value: string) => void;
  placeholder?: string;
}) {
  return (
    <View style={styles.field}>
      <Text style={styles.label}>{label}</Text>
      <TextInput
        autoCapitalize="none"
        autoCorrect={false}
        onChangeText={onChangeText}
        placeholder={placeholder}
        style={styles.input}
        value={value}
      />
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    gap: 14,
    padding: 20,
  },
  title: {
    color: '#111b18',
    fontSize: 28,
    fontWeight: '900',
  },
  description: {
    color: '#64716c',
    fontSize: 14,
    lineHeight: 20,
  },
  field: {
    gap: 6,
  },
  label: {
    color: '#111b18',
    fontSize: 13,
    fontWeight: '800',
  },
  input: {
    borderColor: '#dbe7e1',
    borderRadius: 10,
    borderWidth: 1,
    minHeight: 44,
    paddingHorizontal: 12,
  },
  button: {
    alignItems: 'center',
    backgroundColor: '#0d7568',
    borderRadius: 12,
    flexDirection: 'row',
    gap: 10,
    justifyContent: 'center',
    minHeight: 50,
  },
  buttonDisabled: {
    opacity: 0.72,
  },
  secondaryButton: {
    alignItems: 'center',
    borderColor: '#0d7568',
    borderRadius: 12,
    borderWidth: 1,
    flexDirection: 'row',
    gap: 10,
    justifyContent: 'center',
    minHeight: 48,
  },
  secondaryButtonText: {
    color: '#0d7568',
    fontSize: 15,
    fontWeight: '800',
  },
  buttonText: {
    color: '#fff',
    fontSize: 15,
    fontWeight: '800',
  },
  session: {
    color: '#42534e',
    fontSize: 12,
    lineHeight: 18,
  },
  error: {
    color: '#b42318',
    fontSize: 13,
    fontWeight: '700',
  },
  derivedBox: {
    backgroundColor: '#f5faf7',
    borderColor: '#dbe7e1',
    borderRadius: 10,
    borderWidth: 1,
    gap: 4,
    padding: 10,
  },
  derivedText: {
    color: '#42534e',
    fontSize: 12,
    lineHeight: 17,
  },
  result: {
    backgroundColor: '#10181b',
    borderRadius: 10,
    color: '#eef7f4',
    fontFamily: 'monospace',
    fontSize: 12,
    padding: 12,
  },
});
