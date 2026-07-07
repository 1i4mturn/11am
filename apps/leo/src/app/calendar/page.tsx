"use client";

import { Badge, Button, Card, PageHeader } from "@11am/ui";
import { useCallback, useEffect, useState } from "react";

interface CalendarEvent {
  id: string;
  summary: string;
  start: string;
  end: string;
  location?: string;
}

interface CalendarStatus {
  connected: boolean;
  needsReauth?: boolean;
  authUrl: string | null;
  events: CalendarEvent[];
  message?: string;
  error?: string;
}

export default function CalendarPage() {
  const [status, setStatus] = useState<CalendarStatus | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const [prepId, setPrepId] = useState<string | null>(null);
  const [prep, setPrep] = useState("");
  const [prepLoading, setPrepLoading] = useState(false);

  const [form, setForm] = useState({
    summary: "",
    start: "",
    end: "",
    description: "",
  });

  const load = useCallback(async () => {
    setLoading(true);
    const res = await fetch("/api/calendar");
    setStatus(await res.json());
    setLoading(false);
  }, []);

  useEffect(() => {
    load();
  }, [load]);

  async function createEvent() {
    setError("");
    try {
      const res = await fetch("/api/calendar", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(form),
      });
      const data = await res.json();
      if (!res.ok) throw new Error(data.error);
      setForm({ summary: "", start: "", end: "", description: "" });
      await load();
    } catch (e) {
      setError(e instanceof Error ? e.message : "Create failed");
    }
  }

  async function deleteEvent(eventId: string) {
    if (!confirm("Delete this event?")) return;
    await fetch(`/api/calendar?eventId=${eventId}`, { method: "DELETE" });
    await load();
  }

  async function generatePrep(eventId: string) {
    setPrepId(eventId);
    setPrepLoading(true);
    setPrep("");
    try {
      const res = await fetch("/api/meeting-prep", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ eventId }),
      });
      const data = await res.json();
      if (!res.ok) throw new Error(data.error);
      setPrep(data.brief);
    } catch (e) {
      setPrep(e instanceof Error ? e.message : "Prep failed");
    } finally {
      setPrepLoading(false);
    }
  }

  return (
    <div className="am-section space-y-6">
      <PageHeader
        title="Calendar"
        description="Read and write Google Calendar events. Meeting prep pulls Bolton context."
        actions={
          status?.authUrl && (!status.connected || status.needsReauth) ? (
            <a href={status.authUrl} className="am-btn am-btn-primary px-3 py-1.5 am-label">
              {status.connected ? "Reconnect" : "Connect"}
            </a>
          ) : undefined
        }
      />

      {status?.message && (
        <p className="am-copy text-sm text-[var(--am-muted)]">{status.message}</p>
      )}
      {error && <p className="am-copy text-sm text-red-700">{error}</p>}

      <Card padding="md">
        <p className="am-label mb-3">Create event</p>
        <div className="grid gap-3 md:grid-cols-2">
          <input
            className="am-input"
            placeholder="Title"
            value={form.summary}
            onChange={(e) => setForm({ ...form, summary: e.target.value })}
          />
          <input
            className="am-input"
            type="datetime-local"
            onChange={(e) =>
              setForm({ ...form, start: new Date(e.target.value).toISOString() })
            }
          />
          <input
            className="am-input"
            type="datetime-local"
            onChange={(e) =>
              setForm({ ...form, end: new Date(e.target.value).toISOString() })
            }
          />
          <input
            className="am-input"
            placeholder="Description"
            value={form.description}
            onChange={(e) => setForm({ ...form, description: e.target.value })}
          />
        </div>
        <Button variant="secondary" size="sm" className="mt-3" onClick={createEvent}>
          Create
        </Button>
      </Card>

      <Card padding="md">
        <p className="am-label mb-3">Upcoming events</p>
        {loading ? (
          <p className="am-copy text-sm">Loading…</p>
        ) : status?.events?.length ? (
          <ul className="space-y-3">
            {status.events.map((ev) => (
              <li key={ev.id} className="border-b border-[var(--am-border)] pb-3 last:border-0">
                <div className="flex flex-wrap items-start justify-between gap-2">
                  <div>
                    <p className="am-copy font-medium">{ev.summary}</p>
                    <p className="am-copy text-sm text-[var(--am-muted)]">
                      {new Date(ev.start).toLocaleString()} — {new Date(ev.end).toLocaleString()}
                    </p>
                    {ev.location && (
                      <p className="am-copy text-sm">{ev.location}</p>
                    )}
                  </div>
                  <div className="flex gap-2">
                    <Button variant="ghost" size="sm" onClick={() => generatePrep(ev.id)}>
                      Prep brief
                    </Button>
                    <Button variant="ghost" size="sm" onClick={() => deleteEvent(ev.id)}>
                      Delete
                    </Button>
                  </div>
                </div>
                {prepId === ev.id && (
                  <div className="mt-3 rounded border border-[var(--am-border)] p-3">
                    {prepLoading ? (
                      <p className="am-copy text-sm">Generating brief…</p>
                    ) : (
                      <pre className="am-copy whitespace-pre-wrap text-sm">{prep}</pre>
                    )}
                  </div>
                )}
              </li>
            ))}
          </ul>
        ) : (
          <p className="am-copy text-sm text-[var(--am-muted)]">
            {status?.connected ? "No upcoming events." : "Connect calendar to see events."}
          </p>
        )}
      </Card>
    </div>
  );
}
