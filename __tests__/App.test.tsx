import React from 'react';
import ReactTestRenderer from 'react-test-renderer';
import App from '../App';
import { useLinxChatApp } from '../src/linx/chat/useLinxChatApp';
import type { LinxChatAppState } from '../src/linx/chat/useLinxChatApp';

jest.mock('react-native-markdown-display', () => {
  const ReactMock = require('react');
  const { Text: MockText } = require('react-native');
  return ({ children }: { children: React.ReactNode }) =>
    ReactMock.createElement(MockText, null, children);
});

jest.mock('react-native-safe-area-context', () => {
  const ReactMock = require('react');
  const { View: MockView } = require('react-native');
  return {
    SafeAreaProvider: ({ children }: { children: React.ReactNode }) =>
      ReactMock.createElement(MockView, null, children),
    SafeAreaView: ({ children, style }: { children: React.ReactNode; style?: unknown }) =>
      ReactMock.createElement(MockView, { style }, children),
  };
});

jest.mock('../src/linx/chat/useLinxChatApp', () => ({
  useLinxChatApp: jest.fn(),
}));

const mockedUseLinxChatApp = useLinxChatApp as jest.MockedFunction<
  typeof useLinxChatApp
>;

function makeAppState(
  overrides: Partial<LinxChatAppState> = {},
): LinxChatAppState {
  return {
    phase: 'unauthenticated',
    session: null,
    activeModelId: 'linx-lite',
    threads: [],
    selectedThread: null,
    messages: [],
    isSending: false,
    isLoadingMessages: false,
    login: jest.fn().mockResolvedValue(undefined),
    logout: jest.fn().mockResolvedValue(undefined),
    retry: jest.fn().mockResolvedValue(undefined),
    newChat: jest.fn().mockResolvedValue(undefined),
    selectThread: jest.fn().mockResolvedValue(undefined),
    sendMessage: jest.fn().mockResolvedValue(undefined),
    cancelSend: jest.fn(),
    clearError: jest.fn(),
    ...overrides,
  };
}

test('renders login screen when unauthenticated', async () => {
  mockedUseLinxChatApp.mockReturnValue(makeAppState());

  let renderer: ReactTestRenderer.ReactTestRenderer | undefined;
  await ReactTestRenderer.act(async () => {
    renderer = ReactTestRenderer.create(<App />);
  });

  const loginText = renderer!.root.findAllByProps({
    children: 'Continue with LinX Cloud',
  });
  expect(loginText.length).toBeGreaterThan(0);
  await ReactTestRenderer.act(async () => {
    renderer!.unmount();
  });
});

test('renders chat screen after restore', async () => {
  mockedUseLinxChatApp.mockReturnValue(
    makeAppState({
      phase: 'ready',
      session: {
        issuerUrl: 'https://id.undefineds.co/',
        clientId: 'client',
        webId: 'https://alice.example/profile/card#me',
        accessToken: 'token',
        refreshToken: 'refresh',
        accessTokenExpirationDate: new Date(Date.now() + 60_000).toISOString(),
      },
      selectedThread: {
        id: 'thread-1',
        title: 'Saved Thread',
        createdAt: '1970-01-01T00:00:00.000Z',
        updatedAt: '1970-01-01T00:00:00.000Z',
      },
    }),
  );

  let renderer: ReactTestRenderer.ReactTestRenderer | undefined;
  await ReactTestRenderer.act(async () => {
    renderer = ReactTestRenderer.create(<App />);
  });

  expect(renderer!.root.findByProps({ children: 'Saved Thread' })).toBeTruthy();
  await ReactTestRenderer.act(async () => {
    renderer!.unmount();
  });
});

test('chat composer sends entered text', async () => {
  const sendMessage = jest.fn().mockResolvedValue(undefined);
  mockedUseLinxChatApp.mockReturnValue(
    makeAppState({
      phase: 'ready',
      sendMessage,
      session: {
        issuerUrl: 'https://id.undefineds.co/',
        clientId: 'client',
        webId: 'https://alice.example/profile/card#me',
        accessToken: 'token',
        refreshToken: 'refresh',
        accessTokenExpirationDate: new Date(Date.now() + 60_000).toISOString(),
      },
    }),
  );

  let renderer: ReactTestRenderer.ReactTestRenderer | undefined;
  await ReactTestRenderer.act(async () => {
    renderer = ReactTestRenderer.create(<App />);
  });

  await ReactTestRenderer.act(async () => {
    renderer!.root.findByProps({ testID: 'message-input' }).props.onChangeText('hello');
  });
  await ReactTestRenderer.act(async () => {
    renderer!.root.findByProps({ testID: 'send-button' }).props.onPress();
  });

  expect(sendMessage).toHaveBeenCalledWith('hello');
  await ReactTestRenderer.act(async () => {
    renderer!.unmount();
  });
});
