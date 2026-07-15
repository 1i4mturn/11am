"use client";

import { Button, Card, PageHeader } from "@11am/ui";
import { useCallback, useEffect, useState } from "react";
import { AskBoltonBar } from "@/components/AskBoltonBar";

interface SearchResult {
  id: string;
  title: string;
  entry_type: string;
  source_agent: string;
  summary: string;
}

interface MemoryEntry {
  id: string;
  title: string;
  summary: string;
  entry_type: string;
  source_agent: string;
  status: string;
  cadence?: string | null;
  created_at: string;
}

export default function MemoryFeedPage() {
  const [entries, setEntries] = useState<MemoryEntry[]>([]);
  const [filter, setFilter] = useState("");
  const [loading, setLoading] = useState(true);
  const [editing, setEditing] = useState<string | null>(null);
  const [editSummary, setEditSummary] = useState("");
  const [notice, setNotice] = useState("");
  const [askQuery, setAskQuery] = useState("");
  const [asking, setAsking] = useState(false);
  const [askResults, setAskResults] = useState<SearchResult[] | null>(null);

  async function handleAsk() {
    if (!askQuery.trim()) return;
    setAsking(true);
    setAskResults(null);
    try {
      const res = await fetch("/api/search", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ query: askQuery.trim() }),
      });
      const data = await res.json();
      if (!res.ok) throw new Error(data.error ?? "Search failed");
      setAskResults(data.results ?? []);
    } catch (e) {
      setNotice(e instanceof Error ? e.message : "Search failed");
    } finally {
      setAsking(false);
    }
  }

  const loadEntries = useCallback(async () => {
    const res = await fetch("/api/memory");
    const data = await res.json();
    setEntries(data.entries ?? []);
    setLoading(false);
  }, []);

  useEffect(() => {
    loadEntries();
  }, [loadEntries]);

  async function patchEntry(id: string, updates: Record<string, string>) {
    await fetch("/api/memory", {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ id, ...updates }),
    });
    await loadEntries();
  }

  async function archiveEntry(id: string, title: string) {
    if (!confirm(`Archive "${title}"? Bolton never deletes - this marks it archived.`)) return;
    await fetch(`/api/memory?id=${id}&confirmed=true`, { method: "DELETE" });
    setNotice(`Archived "${title}"`);
    await loadEntries();
  }

  async function saveEdit(id: string) {
    await patchEntry(id, { summary: editSummary });
    setEditing(null);
    setNotice("Entry updated.");
  }

  const filtered = filter
    ? entries.filter(
        (e) =>
          e.source_agent === filter ||
          e.entry_type === filter ||
          e.status === filter
      )
    : entries;

  return (
    <>
      <PageHeader
        title="Memory feed"
        description="Curated institutional memory - tidy, inspectable, source-backed."
        actions={
          <a href="/api/export" className="am-label text-graphite underline">
            export json
          </a>
        }
      />

      <AskBoltonBar
        value={askQuery}
        onChange={setAskQuery}
        onAsk={handleAsk}
        loading={asking}
        onScheduled={setNotice}
      />

      {notice && (
        <Card padding="sm" className="am-section !p-4">
          <p className="am-copy">{notice}</p>
        </Card>
      )}

      {askResults && (
        <Card grain padding="md" className="am-section">
          <p className="am-label mb-3">memory results · “{askQuery}”</p>
          {askResults.length === 0 && <p className="am-copy">nothing found in memory for that.</p>}
          <div className="space-y-4">
            {askResults.map((r) => (
              <div key={r.id} className="am-list-item pt-3 first:pt-0">
                <h3 className="am-title text-sm">{r.title}</h3>
                <p className="am-detail-meta">{r.source_agent} · {r.entry_type} · [{r.id.slice(0, 8)}]</p>
                <p className="am-copy mt-1 text-sm">{r.summary}</p>
              </div>
            ))}
          </div>
        </Card>
      )}

      <div className="am-section flex flex-wrap gap-2">
        {["", "William", "Marc", "Conner", "decision", "voice", "task", "project", "active", "archived", "superseded"].map(
          (f) => (
            <button
              key={f || "all"}
              type="button"
              onClick={() => setFilter(f)}
              className={`am-btn am-label px-3 py-1 ${filter === f ? "am-btn-primary" : "am-btn-secondary"}`}
            >
              {f || "All"}
            </button>
          )
        )}
      </div>

      {loading ? (
        <p className="am-copy">Loading memory…</p>
      ) : (
        <div className="space-y-8">
          {filtered.map((entry) => (
            <Card key={entry.id} grain padding="md">
              <div className="flex items-start justify-between gap-4">
                <div>
                  <h2 className="am-title">{entry.title}</h2>
                  <p className="am-detail-meta mt-1">
                    {entry.source_agent} · {entry.entry_type} · {entry.status}
                    {entry.cadence ? ` · ${entry.cadence}` : ""}
                  </p>
                  <p className="am-label mt-1">[{entry.id.slice(0, 8)}]</p>
                </div>
                <time className="am-label shrink-0">
                  {new Date(entry.created_at).toLocaleDateString()}
                </time>
              </div>

              {editing === entry.id ? (
                <div className="mt-4 space-y-3">
                  <textarea
                    value={editSummary}
                    onChange={(e) => setEditSummary(e.target.value)}
                    rows={4}
                    className="am-input am-copy w-full px-3 py-2"
                  />
                  <div className="flex gap-2">
                    <Button onClick={() => saveEdit(entry.id)} size="sm">
                      Save
                    </Button>
                    <Button onClick={() => setEditing(null)} variant="ghost" size="sm">
                      Cancel
                    </Button>
                  </div>
                </div>
              ) : (
                <p className="am-copy mt-4 leading-relaxed">{entry.summary}</p>
              )}

              {entry.status === "active" && editing !== entry.id && (
                <div className="mt-4 flex flex-wrap gap-2">
                  <Button
                    onClick={() => {
                      setEditing(entry.id);
                      setEditSummary(entry.summary);
                    }}
                    variant="ghost"
                    size="sm"
                  >
                    Edit
                  </Button>
                  <Button
                    onClick={() => archiveEntry(entry.id, entry.title)}
                    variant="ghost"
                    size="sm"
                  >
                    Archive
                  </Button>
                </div>
              )}
            </Card>
          ))}
          {!filtered.length && (
            <p className="am-copy py-12 text-center">
              No memory entries yet. William, Marc, and other agents write here as they work.
            </p>
          )}
        </div>
      )}
    </>
  );
}
