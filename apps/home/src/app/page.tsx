"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { Monogram } from "../components/Monogram";
import { CardGrain } from "../components/CardGrain";
import { AskLeoBar } from "../components/AskLeoBar";
import { AdminSettings } from "../components/AdminSettings";
import { getAgentAppUrl } from "@/lib/agent-urls";
import { AGENTS } from "../data/agents";
import { SIDEBAR_ORDER } from "../data/dashboard";
import type { AgentId } from "../data/agents";
import type {
  ActivityEntry,
  BuildStatus,
  GlanceCard,
} from "../data/dashboard";

function getGreeting(): string {
  const hour = new Date().getHours();
  if (hour < 12) return "good morning";
  if (hour < 17) return "good afternoon";
  return "good evening";
}

function agentById(id: AgentId) {
  return AGENTS.find((a) => a.id === id)!;
}

function StatusPill({ status }: { status: BuildStatus }) {
  return (
    <span className={`roster-status roster-status--${status}`}>
      {status === "live" && "live"}
      {status === "build" && "in build"}
      {status === "urgent" && "urgent"}
    </span>
  );
}

function GlanceTag({ tag }: { tag: "urgent" | "ready" | "info" }) {
  const label = tag === "info" ? "today" : tag;
  return <span className={`glance-tag glance-tag--${tag}`}>{label}</span>;
}

export default function DashboardPage() {
  const [greeting, setGreeting] = useState("good afternoon");
  const [glance, setGlance] = useState<GlanceCard[]>([]);
  const [activity, setActivity] = useState<ActivityEntry[]>([]);
  const [roster, setRoster] = useState<Array<{ agentId: AgentId; build_status: BuildStatus }>>([]);
  const leoInputRef = useRef<HTMLInputElement>(null);

  const loadDashboard = useCallback(async () => {
    const res = await fetch("/api/dashboard", { cache: "no-store" });
    if (res.ok) {
      const data = await res.json();
      setGlance(data.glance ?? []);
      setActivity(data.activity ?? []);
      setRoster(data.roster ?? []);
    }
  }, []);

  useEffect(() => {
    setGreeting(getGreeting());
    void loadDashboard();
    const interval = setInterval(() => void loadDashboard(), 60_000);
    return () => clearInterval(interval);
  }, [loadDashboard]);

  useEffect(() => {
    const onKeyDown = (event: KeyboardEvent) => {
      if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === "k") {
        event.preventDefault();
        leoInputRef.current?.focus();
      }
    };
    window.addEventListener("keydown", onKeyDown);
    return () => window.removeEventListener("keydown", onKeyDown);
  }, []);

  return (
    <>
      <div className="gradient-wash" aria-hidden="true" />
      <div className="gradient-wash-white" aria-hidden="true" />

      <svg className="grain grain-coarse" xmlns="http://www.w3.org/2000/svg" aria-hidden="true">
        <filter id="grain-coarse">
          <feTurbulence type="fractalNoise" baseFrequency="0.9" numOctaves="2" stitchTiles="stitch" />
          <feColorMatrix type="saturate" values="0" />
        </filter>
        <rect width="100%" height="100%" filter="url(#grain-coarse)" />
      </svg>
      <svg className="grain grain-fine" xmlns="http://www.w3.org/2000/svg" aria-hidden="true">
        <filter id="grain-fine">
          <feTurbulence type="fractalNoise" baseFrequency="0.35" numOctaves="2" stitchTiles="stitch" />
          <feColorMatrix type="saturate" values="0" />
        </filter>
        <rect width="100%" height="100%" filter="url(#grain-fine)" />
      </svg>

      <div className="shell">
        <aside className="sidebar">
          <div className="sidebar-logo">
            <Monogram id="logo" variant="emboss-light" className="sidebar-logo-mono" />
          </div>

          <div className="agent-grid">
            {SIDEBAR_ORDER.map((id) => {
              const agent = agentById(id);
              const icon = <Monogram id={id} variant="flat" className="agent-square-icon" />;
              const href = getAgentAppUrl(id);
              if (href) {
                return (
                  <a key={id} href={href} className="agent-square" aria-label={agent.name}>
                    {icon}
                  </a>
                );
              }
              return (
                <button key={id} type="button" className="agent-square" aria-label={agent.name} disabled>
                  {icon}
                </button>
              );
            })}
          </div>
        </aside>

        <main className="main">
          <h1 className="greeting">{greeting}, liam</h1>

          <AskLeoBar inputRef={leoInputRef} />

          <h2 className="glance-title">what&apos;s happening today</h2>
          <div className="glance-grid">
            {glance.map((card) => (
              <article key={card.kicker} className="glance-card">
                <CardGrain />
                <div className="glance-kicker">
                  <Monogram id={card.agentId} variant="flat" className="mono-tiny" />
                  {card.kicker}
                </div>
                {card.rows.map((row, i) => (
                  <div key={i} className="glance-row">
                    {row.who ? (
                      <>
                        <span className="who">{row.who}</span> {row.text}
                      </>
                    ) : (
                      <span className="why">{row.text}</span>
                    )}
                    {row.tag && <GlanceTag tag={row.tag} />}
                  </div>
                ))}
              </article>
            ))}
          </div>

          <div className="board">
            <section className="panel">
              <CardGrain />
              <h2 className="panel-title">activity</h2>
              <div className="timeline">
                {activity.length === 0 && (
                  <p className="activity-empty">no recent bolton activity - start bolton on :3002</p>
                )}
                {activity.map((entry, index) => (
                  <div key={`${entry.agentId}-${index}`} className="timeline-row">
                    <div className="timeline-rail">
                      <div className="timeline-dot">
                        <Monogram id={entry.agentId} variant="emboss-bottom" />
                      </div>
                      {index < activity.length - 1 && <div className="timeline-line" />}
                    </div>
                    <div className="activity-body">
                      <div className="activity-agent">
                        <span>{entry.agentId}</span>
                        <span className="activity-time">{entry.time}</span>
                      </div>
                      <p className="activity-text">{entry.text}</p>
                    </div>
                  </div>
                ))}
              </div>
            </section>

            <section className="panel">
              <CardGrain />
              <h2 className="panel-title">roster</h2>
              <div className="roster-list">
                {roster.map(({ agentId, build_status }) => {
                  const agent = agentById(agentId);
                  return (
                    <div key={agentId} className="roster-row">
                      <Monogram id={agentId} variant="flat" className="roster-mono" />
                      <div>
                        <div className="roster-name">{agent.name}</div>
                        <div className="roster-role">{agent.role}</div>
                      </div>
                      <StatusPill status={build_status} />
                    </div>
                  );
                })}
              </div>
            </section>
          </div>

          <AdminSettings />
        </main>
      </div>

      <div className="bottom-row">
        {SIDEBAR_ORDER.map((id) => {
          const agent = agentById(id);
          const mono = (
            <Monogram
              id={id}
              variant="emboss-bottom"
              className="bottom-mono"
              title={agent.name}
            />
          );
          const href = getAgentAppUrl(id);
          if (href) {
            return (
              <a key={id} href={href} className="bottom-mono-link" aria-label={`open ${agent.name}`}>
                {mono}
              </a>
            );
          }
          return <div key={id}>{mono}</div>;
        })}
      </div>
    </>
  );
}
