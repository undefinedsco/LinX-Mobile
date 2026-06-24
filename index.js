/**
 * @format
 */

import { AppRegistry } from 'react-native';
import App from './App';
import P2PSmokeApp from './src/p2p-smoke/P2PSmokeApp';
import { name as appName } from './app.json';

AppRegistry.registerComponent(appName, () => App);
AppRegistry.registerComponent('LinXP2PSmoke', () => P2PSmokeApp);
