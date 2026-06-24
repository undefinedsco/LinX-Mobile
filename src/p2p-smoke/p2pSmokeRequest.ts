/* eslint-disable no-bitwise */
import { makeUUID } from '../linx/utils';
import {
  deriveApiBaseUrlFromIdp,
  deriveNodeIdFromStorageUrl,
  resolveSmokeResourceUrl,
} from './deriveP2PSmokeTarget';

const RAW_TCP_HOLE_PUNCH_TRANSPORT = 'raw-tcp-hole-punch';
export const RAW_TCP_HOLE_PUNCH_CAPABILITY = 'tcp-punch';
export const XPOD_P2P_HTTP_PROTOCOL = 'xpod-p2p-http/1';
const DEFAULT_CONNECT_TIMEOUT_MS = 8_000;
const DEFAULT_WAIT_TIMEOUT_MS = 20_000;
const DEFAULT_POLL_INTERVAL_MS = 1_000;
const DEFAULT_REQUEST_TIMEOUT_MS = 10_000;
const DEFAULT_WINDOW_SECONDS = 42;
const DEFAULT_MAX_CLOCK_ERROR_SECONDS = 20;
const DEFAULT_MIN_RUN_WINDOW_SECONDS = 10;
const DEFAULT_NUM_PORTS = 8;
const DEFAULT_BASE_PORT = 30_000;
const DEFAULT_PORT_RANGE = 20_000;
const LARGE_PRIME = 2_654_435_761;

export interface P2PSmokeInput {
  idpUrl: string;
  storageUrl: string;
  resourcePath?: string;
  token?: string;
  clientId?: string;
  apiBaseUrl?: string;
  nodeId?: string;
  writeBody?: string;
}

interface TcpHolePunchPlan {
  bucket: number;
  boundary: number;
  rendezvousTimeSeconds: number;
  ports: number[];
}

export interface P2PTransportCandidate {
  id: string;
  role: 'client' | 'node';
  sourceId: string;
  createdAt: string;
  protocol?: string;
  transport?: string;
  host?: string;
  address?: string;
  url?: string;
  port?: number;
  priority?: number;
  metadata?: Record<string, unknown>;
}

export interface NativeP2PSmokeRequest {
  protocol: typeof XPOD_P2P_HTTP_PROTOCOL;
  apiBaseUrl: string;
  signalSessionsUrl: string;
  nodeId: string;
  clientId: string;
  targetUrl: string;
  method: string;
  headers: Record<string, string>;
  body: string;
  token?: string;
  connectTimeoutMs: number;
  waitTimeoutMs: number;
  pollIntervalMs: number;
  requestTimeoutMs: number;
  localCandidates: P2PTransportCandidate[];
}

export function buildP2PSmokeRequest(input: P2PSmokeInput): NativeP2PSmokeRequest {
  const apiBaseUrl = ensureTrailingSlash(input.apiBaseUrl ?? deriveApiBaseUrlFromIdp(input.idpUrl));
  const nodeId = input.nodeId ?? deriveNodeIdFromStorageUrl(input.storageUrl);
  const clientId = input.clientId || `linx-mobile-${makeUUID()}`;
  const targetUrl = resolveSmokeResourceUrl({
    storageUrl: input.storageUrl,
    resourcePath: input.resourcePath,
  });
  const now = new Date();
  const plan = computeTcpHolePunchPlan();
  const localCandidates = createRawTcpHolePunchCandidates({
    role: 'client',
    sourceId: clientId,
    createdAt: now,
    plan,
  });
  const headers: Record<string, string> = {
    accept: 'text/plain, */*',
    'content-type': 'text/plain; charset=utf-8',
  };
  if (input.token) {
    headers.authorization = `Bearer ${input.token}`;
  }

  return {
    protocol: XPOD_P2P_HTTP_PROTOCOL,
    apiBaseUrl,
    signalSessionsUrl: new URL(
      `/v1/signal/nodes/${encodeURIComponent(nodeId)}/sessions`,
      apiBaseUrl,
    ).toString(),
    nodeId,
    clientId,
    targetUrl,
    method: 'PUT',
    headers,
    body: input.writeBody ?? `linx-mobile-p2p-smoke ${new Date().toISOString()}\n`,
    ...(input.token ? { token: input.token } : {}),
    connectTimeoutMs: DEFAULT_CONNECT_TIMEOUT_MS,
    waitTimeoutMs: DEFAULT_WAIT_TIMEOUT_MS,
    pollIntervalMs: DEFAULT_POLL_INTERVAL_MS,
    requestTimeoutMs: DEFAULT_REQUEST_TIMEOUT_MS,
    localCandidates,
  };
}

function createRawTcpHolePunchCandidates(options: {
  role: 'client' | 'node';
  sourceId: string;
  createdAt: Date;
  plan: TcpHolePunchPlan;
}): P2PTransportCandidate[] {
  return options.plan.ports.map((port, index) => ({
    id: `${options.sourceId}_${options.plan.bucket}_${port}_${index}`,
    role: options.role,
    sourceId: options.sourceId,
    createdAt: options.createdAt.toISOString(),
    protocol: 'tcp',
    transport: RAW_TCP_HOLE_PUNCH_TRANSPORT,
    port,
    priority: 100 - index,
    metadata: {
      provider: RAW_TCP_HOLE_PUNCH_TRANSPORT,
      bucket: options.plan.bucket,
      boundary: options.plan.boundary,
      rendezvousTimeSeconds: options.plan.rendezvousTimeSeconds,
    },
  }));
}

function computeTcpHolePunchPlan(): TcpHolePunchPlan {
  const nowSeconds = Math.floor(Date.now() / 1_000);
  let bucket = Math.floor((nowSeconds - DEFAULT_MAX_CLOCK_ERROR_SECONDS) / DEFAULT_WINDOW_SECONDS);
  let rendezvousTimeSeconds = (bucket + 1) * DEFAULT_WINDOW_SECONDS + DEFAULT_MAX_CLOCK_ERROR_SECONDS;
  if (rendezvousTimeSeconds - nowSeconds < DEFAULT_MIN_RUN_WINDOW_SECONDS) {
    bucket += 1;
    rendezvousTimeSeconds = (bucket + 1) * DEFAULT_WINDOW_SECONDS + DEFAULT_MAX_CLOCK_ERROR_SECONDS;
  }
  const boundary = stableBoundary(bucket);
  return {
    bucket,
    boundary,
    rendezvousTimeSeconds,
    ports: stablePorts(boundary, DEFAULT_NUM_PORTS, DEFAULT_BASE_PORT, DEFAULT_PORT_RANGE),
  };
}

function stableBoundary(bucket: number): number {
  return Math.imul(bucket >>> 0, LARGE_PRIME >>> 0) >>> 0;
}

function stablePorts(boundary: number, count: number, basePort: number, portRange: number): number[] {
  const rng = mulberry32(boundary >>> 0);
  const ports = new Set<number>();
  while (ports.size < count) {
    ports.add(basePort + Math.floor(rng() * portRange));
  }
  return Array.from(ports).sort((left, right) => right - left);
}

function mulberry32(seed: number): () => number {
  let value = seed;
  return () => {
    value = (value + 0x6D2B79F5) | 0;
    let result = Math.imul(value ^ (value >>> 15), 1 | value);
    result ^= result + Math.imul(result ^ (result >>> 7), 61 | result);
    return ((result ^ (result >>> 14)) >>> 0) / 4_294_967_296;
  };
}

function ensureTrailingSlash(value: string): string {
  return value.endsWith('/') ? value : `${value}/`;
}
