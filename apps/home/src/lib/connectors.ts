import { CONNECTORS } from "@/data/connectors";
import {
  GEORGE_API_URL,
  LEO_API_URL,
  MARC_API_URL,
  WILLIAM_API_URL,
} from "@/lib/config";

export interface ConnectorStatus {
  id: string;
  name: string;
  agent: string;
  agentId: string;
  description: string;
  appUrl: string;
  setupUrl: string;
  connected: boolean;
  needsReauth: boolean;
  authUrl: string | null;
  message?: string;
  envHint: string;
  offline?: boolean;
}

const BASE_BY_AGENT: Record<string, string> = {
  marc: MARC_API_URL,
  william: WILLIAM_API_URL,
  leo: LEO_API_URL,
  george: GEORGE_API_URL,
};

const APP_URL_BY_AGENT: Record<string, string> = {
  marc: MARC_API_URL,
  william: WILLIAM_API_URL,
  leo: LEO_API_URL,
  george: GEORGE_API_URL,
};

async function fetchConnectorStatus(
  def: (typeof CONNECTORS)[number]
): Promise<ConnectorStatus> {
  const base = BASE_BY_AGENT[def.agentId] ?? def.appUrl;
  const setupUrl = `${(APP_URL_BY_AGENT[def.agentId] ?? def.appUrl).replace(/\/$/, "")}${def.setupPath}`;

  const fallback: ConnectorStatus = {
    id: def.id,
    name: def.name,
    agent: def.agent,
    agentId: def.agentId,
    description: def.description,
    appUrl: APP_URL_BY_AGENT[def.agentId] ?? def.appUrl,
    setupUrl,
    connected: false,
    needsReauth: false,
    authUrl: null,
    message: `${def.agent} offline - start app on ${APP_URL_BY_AGENT[def.agentId] ?? def.appUrl}`,
    envHint: def.envHint,
    offline: true,
  };

  try {
    const res = await fetch(`${base}${def.statusPath}`, { cache: "no-store" });
    const data = await res.json();

    if (!res.ok && data.error) {
      return {
        ...fallback,
        offline: false,
        message: String(data.error),
      };
    }

    return {
      id: def.id,
      name: def.name,
      agent: def.agent,
      agentId: def.agentId,
      description: def.description,
      appUrl: APP_URL_BY_AGENT[def.agentId] ?? def.appUrl,
      setupUrl,
      connected: Boolean(data.connected),
      needsReauth: Boolean(data.needsReauth),
      authUrl: typeof data.authUrl === "string" ? data.authUrl : null,
      message: typeof data.message === "string" ? data.message : undefined,
      envHint: def.envHint,
      offline: false,
    };
  } catch {
    return fallback;
  }
}

export async function loadConnectorStatuses(): Promise<ConnectorStatus[]> {
  return Promise.all(CONNECTORS.map(fetchConnectorStatus));
}
