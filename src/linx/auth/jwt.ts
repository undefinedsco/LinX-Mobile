import { LinxAppError } from '../errors';

function decodeBase64Url(value: string): string {
  const normalized = value.replace(/-/g, '+').replace(/_/g, '/');
  const padded = normalized.padEnd(
    normalized.length + ((4 - (normalized.length % 4)) % 4),
    '=',
  );
  const alphabet =
    'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=';
  let output = '';

  for (let index = 0; index < padded.length; index += 4) {
    const encoded1 = alphabet.indexOf(padded.charAt(index));
    const encoded2 = alphabet.indexOf(padded.charAt(index + 1));
    const encoded3 = alphabet.indexOf(padded.charAt(index + 2));
    const encoded4 = alphabet.indexOf(padded.charAt(index + 3));

    const byte1 = encoded1 * 4 + Math.floor(encoded2 / 16);
    const byte2 = (encoded2 % 16) * 16 + Math.floor(encoded3 / 4);
    const byte3 = (encoded3 % 4) * 64 + encoded4;

    output += String.fromCharCode(byte1);
    if (encoded3 !== 64) {
      output += String.fromCharCode(byte2);
    }
    if (encoded4 !== 64) {
      output += String.fromCharCode(byte3);
    }
  }

  try {
    return decodeURIComponent(
      output
        .split('')
        .map(char => `%${char.charCodeAt(0).toString(16).padStart(2, '0')}`)
        .join(''),
    );
  } catch {
    return output;
  }
}

function isUrlLikeWebId(value: unknown): value is string {
  if (typeof value !== 'string') {
    return false;
  }

  try {
    const parsed = new URL(value);
    return parsed.protocol === 'https:' || parsed.protocol === 'http:';
  } catch {
    return false;
  }
}

export function decodeJwtPayload(token: string): Record<string, unknown> {
  const parts = token.split('.');
  if (parts.length < 2 || !parts[1]) {
    throw new LinxAppError('The ID token did not contain a valid payload.');
  }

  try {
    return JSON.parse(decodeBase64Url(parts[1])) as Record<string, unknown>;
  } catch {
    throw new LinxAppError('The ID token payload was not valid JSON.');
  }
}

export function extractWebIdFromIdToken(token: string): string {
  const payload = decodeJwtPayload(token);
  if (isUrlLikeWebId(payload.webid)) {
    return payload.webid;
  }
  if (isUrlLikeWebId(payload.webId)) {
    return payload.webId;
  }
  if (isUrlLikeWebId(payload.sub)) {
    return payload.sub;
  }
  throw new LinxAppError('The ID token did not contain a valid WebID.');
}
