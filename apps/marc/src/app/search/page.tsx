"use client";

import { Button, Card, PageHeader } from "@11am/ui";
import { useState } from "react";

interface SearchResult {
  message_id: string;
  sender: string;
  subject: string;
  date: string;
  why_matched: string;
  thread_summary: string;
  suggested_action: string;
}

export default function SearchPage() {
  const [query, setQuery] = useState("");
  const [results, setResults] = useState<SearchResult[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");

  async function handleSearch(e: React.FormEvent) {
    e.preventDefault();
    if (!query.trim()) return;
    setLoading(true);
    setError("");
    try {
      const res = await fetch("/api/search", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ query }),
      });
      const data = await res.json();
      if (!res.ok) throw new Error(data.error);
      setResults(data.results);
    } catch (e) {
      setError(e instanceof Error ? e.message : "Search failed");
    } finally {
      setLoading(false);
    }
  }

  return (
    <>
      <PageHeader
        title="Search your inbox"
        description={'Natural language search — "Find the email where JC mentioned the Xero bank feed issue"'}
      />

      <form onSubmit={handleSearch} className="am-section flex gap-3">
        <input
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          placeholder="What are you looking for?"
          className="am-input am-copy flex-1 px-4 py-3"
        />
        <Button type="submit" disabled={loading} size="lg">
          {loading ? "Searching…" : "Search"}
        </Button>
      </form>

      {error && (
        <Card padding="sm" className="am-section !p-4">
          <p className="am-copy">{error}</p>
        </Card>
      )}

      <div className="space-y-8">
        {results.map((r) => (
          <Card key={r.message_id} padding="md">
            <div className="flex justify-between gap-4">
              <p className="am-title">{r.sender}</p>
              <p className="am-label">{new Date(r.date).toLocaleDateString()}</p>
            </div>
            <p className="am-copy mt-2">{r.subject}</p>
            <p className="am-detail-meta mt-3">{r.why_matched}</p>
            <p className="am-copy mt-3">{r.thread_summary}</p>
            <p className="am-detail-meta mt-2">{r.suggested_action}</p>
          </Card>
        ))}
      </div>
    </>
  );
}
