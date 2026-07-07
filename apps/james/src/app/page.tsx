"use client";

import { Badge, Card, PageHeader } from "@11am/ui";
import { useState } from "react";
import { AskJamesBar } from "@/components/AskJamesBar";
import { briefToMarkdown } from "@/lib/research/template";
import type { JamesHandoff, RequestType } from "@/lib/types";

const REQUEST_TYPES: { value: RequestType; label: string }[] = [
  { value: "general", label: "General" },
  { value: "market", label: "Market" },
  { value: "technical", label: "Technical" },
  { value: "pricing", label: "Pricing" },
  { value: "cultural", label: "Cultural" },
  { value: "academic", label: "Academic" },
];

export default function ResearchPage() {
  const [query, setQuery] = useState(
    "Compare voice-fidelity AI writing tools for solo founders — differentiation vs generic assistants"
  );
  const [requestType, setRequestType] = useState<RequestType>("market");
  const [handoff, setHandoff] = useState<JamesHandoff | null>(null);
  const [loading, setLoading] = useState(false);
  const [notice, setNotice] = useState("");
  const [error, setError] = useState("");

  async function handleAsk() {
    if (!query.trim()) return;
    setLoading(true);
    setError("");
    setHandoff(null);
    try {
      const res = await fetch("/api/research", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          research_question: query.trim(),
          request_type: requestType,
        }),
      });
      const data = await res.json();
      if (!res.ok) throw new Error(data.error);
      setHandoff(data.handoff);
    } catch (e) {
      setError(e instanceof Error ? e.message : "Research failed");
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="am-section space-y-6">
      <PageHeader
        title="Research"
        description="Web search with citations. James returns a structured brief — never a raw thread dump."
      />

      <div className="flex flex-wrap gap-2">
        {REQUEST_TYPES.map((t) => (
          <button
            key={t.value}
            type="button"
            onClick={() => setRequestType(t.value)}
            className={`am-btn am-copy px-3 py-1.5 text-xs ${
              requestType === t.value ? "am-btn-primary" : "am-btn-secondary"
            }`}
          >
            {t.label}
          </button>
        ))}
      </div>

      <AskJamesBar
        value={query}
        onChange={setQuery}
        onAsk={handleAsk}
        loading={loading}
        onScheduled={setNotice}
        taskType={requestType === "pricing" ? "pricing_check" : requestType === "market" ? "market_scan" : "research"}
      />

      {notice && <p className="am-copy text-sm">{notice}</p>}
      {error && <p className="am-copy am-error text-sm">{error}</p>}

      {handoff && (
        <>
          <div className="flex flex-wrap gap-2">
            <Badge tone="medium">{handoff.request_type}</Badge>
            <Badge tone="low">{handoff.depth} · {handoff.search_uses ?? "?"} searches</Badge>
            {handoff.saved_to_bolton && <Badge tone="high">Saved to Bolton</Badge>}
            {handoff.prior_research_used && handoff.prior_research_used.length > 0 && (
              <Badge tone="low">Prior research reused</Badge>
            )}
          </div>

          {handoff.prior_research_used && handoff.prior_research_used.length > 0 && (
            <Card padding="md">
              <p className="am-label mb-2">Prior research checked</p>
              <ul className="am-copy space-y-1 text-sm text-[var(--am-muted)]">
                {handoff.prior_research_used.map((p) => (
                  <li key={p.id}>{p.title}</li>
                ))}
              </ul>
            </Card>
          )}

          <Card padding="lg">
            <pre className="am-copy whitespace-pre-wrap text-sm">
              {briefToMarkdown(handoff)}
            </pre>
          </Card>
        </>
      )}

      <Card padding="md">
        <p className="am-label mb-2">Locked template</p>
        <p className="am-copy text-sm text-[var(--am-muted)]">
          Research question → Key findings → What this means → Recommendation → Sources
        </p>
      </Card>
    </div>
  );
}
