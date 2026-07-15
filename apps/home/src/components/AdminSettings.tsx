"use client";

import { useCallback, useEffect, useState } from "react";
import { Monogram } from "./Monogram";
import { CardGrain } from "./CardGrain";
import type { AgentId } from "@/data/agents";

interface ConnectorStatus {
  id: string;
  name: string;
  agent: string;
  agentId: AgentId;
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

function StatusPill({ connector }: { connector: ConnectorStatus }) {
  if (connector.offline) {
    return <span className="connector-status connector-status--offline">offline</span>;
  }
  if (connector.connected && !connector.needsReauth) {
    return <span className="connector-status connector-status--live">connected</span>;
  }
  if (connector.needsReauth) {
    return <span className="connector-status connector-status--urgent">reconnect</span>;
  }
  return <span className="connector-status connector-status--build">not connected</span>;
}

export function AdminSettings() {
  const [connectors, setConnectors] = useState<ConnectorStatus[]>([]);
  const [loading, setLoading] = useState(true);

  const load = useCallback(async () => {
    setLoading(true);
    try {
      const res = await fetch("/api/connectors", { cache: "no-store" });
      if (res.ok) {
        const data = await res.json();
        setConnectors(data.connectors ?? []);
      }
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

  return (
    <section className="admin-settings">
      <div className="admin-settings-header">
        <h2 className="panel-title">admin · connectors</h2>
        <button type="button" className="admin-refresh" onClick={() => void load()}>
          refresh
        </button>
      </div>

      <p className="admin-settings-note">
        Single-user debug - Google Cloud apps stay in Testing mode. OAuth links open the provider
        consent screen directly when credentials are configured.
      </p>

      <div className="connector-grid">
        {loading && connectors.length === 0 && (
          <p className="admin-settings-note">loading connector status…</p>
        )}

        {connectors.map((c) => (
          <article key={c.id} className="connector-card">
            <CardGrain />
            <div className="connector-card-head">
              <Monogram id={c.agentId} variant="flat" className="connector-mono" />
              <div>
                <p className="connector-name">{c.name}</p>
                <p className="connector-agent">via {c.agent}</p>
              </div>
              <StatusPill connector={c} />
            </div>

            <p className="connector-desc">{c.description}</p>

            {c.message && <p className="connector-message">{c.message}</p>}

            <div className="connector-actions">
              {c.authUrl && (!c.connected || c.needsReauth) ? (
                <a href={c.authUrl} className="connector-btn connector-btn--primary">
                  {c.needsReauth ? "Reconnect OAuth" : "Connect OAuth"}
                </a>
              ) : c.connected && !c.needsReauth ? (
                <span className="connector-btn connector-btn--muted">oauth active</span>
              ) : (
                <a href={c.setupUrl} className="connector-btn connector-btn--secondary">
                  Open setup
                </a>
              )}
              <a href={c.setupUrl} className="connector-btn connector-btn--ghost">
                {c.agent} app
              </a>
            </div>

            <p className="connector-env">{c.envHint}</p>
          </article>
        ))}
      </div>
    </section>
  );
}
