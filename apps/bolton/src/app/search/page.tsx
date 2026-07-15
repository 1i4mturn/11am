"use client";

import { Button, Card, PageHeader } from "@11am/ui";
import { useState } from "react";

interface SearchResult {
  id: string;
  title: string;
  entry_type: string;
  source_agent: string;
  why_matched: string;
  summary: string;
  citation: string;
  date: string;
}

export default function SearchPage() {
  const [query, setQuery] = useState("");
  const [results, setResults] = useState<SearchResult[]>([]);
  const [loading, setLoading] = useState(false);
  const [expanded, setExpanded] = useState<string | null>(null);
  const [detail, setDetail] = useState<Record<string, unknown> | null>(null);

  async function handleSearch(e: React.FormEvent) {
    e.preventDefault();
    setLoading(true);
    const res = await fetch("/api/search", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ query }),
    });
    const data = await res.json();
    setResults(data.results ?? []);
    setLoading(false);
  }

  async function openCitation(id: string) {
    if (expanded === id) {
      setExpanded(null);
      setDetail(null);
      return;
    }
    const res = await fetch(`/api/memory?id=${id}`);
    const data = await res.json();
    setExpanded(id);
    setDetail(data.entry ?? null);
  }

  return (
    <>
      <PageHeader
        title="Search memory"
        description={
          '"What did we decide about William\'s voice profile?" - natural language, cited source cards.'
        }
      />
      <form onSubmit={handleSearch} className="am-section flex gap-3">
        <input
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          placeholder="Describe what you're looking for…"
          className="am-input am-copy flex-1 px-4 py-3"
        />
        <Button type="submit" disabled={loading} size="lg">
          {loading ? "Searching…" : "Search"}
        </Button>
      </form>
      <div className="space-y-8">
        {results.map((r) => (
          <Card key={r.id} grain padding="md">
            <div className="flex items-start justify-between gap-4">
              <div>
                <p className="am-title">{r.title}</p>
                <p className="am-detail-meta mt-1">
                  {r.source_agent} · {r.entry_type} · {r.why_matched}
                </p>
              </div>
              <button
                type="button"
                onClick={() => openCitation(r.id)}
                className="am-label shrink-0 underline"
              >
                {r.citation}
              </button>
            </div>
            <p className="am-copy mt-3">{r.summary}</p>
            {expanded === r.id && detail && (
              <div className="mt-4 border-t border-border pt-4">
                <p className="am-label mb-2">cited entry</p>
                <p className="am-detail-meta">Status: {String(detail.status)}</p>
                {"full_content" in detail && typeof detail.full_content === "string" && (
                  <pre className="am-copy mt-3 max-h-48 overflow-auto whitespace-pre-wrap text-sm">
                    {detail.full_content.slice(0, 2000)}
                  </pre>
                )}
              </div>
            )}
          </Card>
        ))}
      </div>
    </>
  );
}
