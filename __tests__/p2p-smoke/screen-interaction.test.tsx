import React from 'react';
import ReactTestRenderer from 'react-test-renderer';
import { TextInput } from 'react-native';
import { P2PSmokeScreen } from '../../src/p2p-smoke/P2PSmokeScreen';
import { runP2PSmoke } from '../../src/p2p-smoke/mobileP2PSmoke';
import type { LinxAuthSession } from '../../src/linx/types';

jest.mock('../../src/p2p-smoke/mobileP2PSmoke', () => ({
  createP2PSmokeAuthController: jest.fn(),
  formatP2PSmokeEvidenceForShare: jest.fn(() => '{}'),
  runP2PSmoke: jest.fn(async () => ({
    smokeOk: true,
    route: { kind: 'p2p' },
    connectorEvents: [],
  })),
}));

const cloudSession: LinxAuthSession = {
  issuerUrl: 'https://id.undefineds.co/',
  clientId: 'client',
  webId: 'https://id.undefineds.co/alice/profile/card#me',
  accessToken: 'cloud-access-token',
  refreshToken: 'refresh',
  accessTokenExpirationDate: '2099-01-01T00:00:00.000Z',
  storageServerUrl: 'https://node-0000.undefineds.co/',
};

function findInputByValue(
  renderer: ReactTestRenderer.ReactTestRenderer,
  value: string,
) {
  return renderer.root.findAllByType(TextInput).find(input => input.props.value === value);
}

function findButtonByText(
  renderer: ReactTestRenderer.ReactTestRenderer,
  text: string,
) {
  return renderer.root.findAll(node =>
    typeof node.props.onPress === 'function' && nodeContainsText(node, text),
  )[0];
}

function nodeContainsText(node: ReactTestRenderer.ReactTestInstance, text: string): boolean {
  for (const child of node.children) {
    if (child === text) {
      return true;
    }
    if (typeof child !== 'string' && nodeContainsText(child, text)) {
      return true;
    }
  }
  return false;
}

test('applying a local SP gives visible feedback and keeps cloud IDP login', async () => {
  let renderer: ReactTestRenderer.ReactTestRenderer | undefined;

  await ReactTestRenderer.act(async () => {
    renderer = ReactTestRenderer.create(
      <P2PSmokeScreen
        embeddedInChat
        initialSession={cloudSession}
        initialSmokeDefaults={{
          idpUrl: 'https://id.undefineds.co/',
          storageUrl: 'https://node-0000.undefineds.co/alice/',
          localSpUrl: 'https://node-0000.undefineds.co/',
        }}
      />,
    );
  });

  const localSpInput = renderer!.root.findByProps({
    placeholder: 'https://node-0000.undefineds.co/',
  });
  await ReactTestRenderer.act(async () => {
    localSpInput.props.onChangeText('https://node-0001.undefineds.co/');
  });

  await ReactTestRenderer.act(async () => {
    findButtonByText(renderer!, 'Apply local SP')!.props.onPress({ nativeEvent: {} });
  });

  expect(renderer!.root.findByProps({
    children: 'Local SP applied: https://node-0001.undefineds.co/',
  })).toBeTruthy();
  expect(findInputByValue(renderer!, 'https://node-0001.undefineds.co/alice/')).toBeTruthy();
  expect(findInputByValue(renderer!, 'https://id.undefineds.co/')).toBeTruthy();
  expect(renderer!.root.findByProps({ children: 'Using current chat login' })).toBeTruthy();
});

test('running smoke after applying local SP uses cloud token against local storage', async () => {
  const mockedRunP2PSmoke = runP2PSmoke as jest.MockedFunction<typeof runP2PSmoke>;
  mockedRunP2PSmoke.mockClear();
  let renderer: ReactTestRenderer.ReactTestRenderer | undefined;

  await ReactTestRenderer.act(async () => {
    renderer = ReactTestRenderer.create(
      <P2PSmokeScreen
        embeddedInChat
        initialSession={cloudSession}
        initialSmokeDefaults={{
          idpUrl: 'https://id.undefineds.co/',
          storageUrl: 'https://node-0000.undefineds.co/alice/',
          localSpUrl: 'https://node-0000.undefineds.co/',
        }}
      />,
    );
  });

  await ReactTestRenderer.act(async () => {
    renderer!.root
      .findByProps({ placeholder: 'https://node-0000.undefineds.co/' })
      .props.onChangeText('https://node-0001.undefineds.co/');
  });
  await ReactTestRenderer.act(async () => {
    findButtonByText(renderer!, 'Apply local SP')!.props.onPress();
  });
  await ReactTestRenderer.act(async () => {
    findButtonByText(renderer!, 'Run P2P write/read smoke')!.props.onPress();
  });

  expect(mockedRunP2PSmoke).toHaveBeenCalledWith(expect.objectContaining({
    idpUrl: 'https://id.undefineds.co/',
    storageUrl: 'https://node-0001.undefineds.co/alice/',
    token: 'cloud-access-token',
  }));
});
