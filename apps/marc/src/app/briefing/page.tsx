"use client";

import { Button, Card, PageHeader } from "@11am/ui";
import { useState } from "react";

export default function BriefingPage() {
  const [briefing, setBriefing] = useState<Record<string, unknown> | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");

  async function load(type: "daily" | "weekly") {
    setLoading(true);
    setError("");
    try {
      const res = await fetch(`/api/briefings?type=${type}`);
      const data = await res.json();
      if (!res.ok) throw new Error(data.error);
      setBriefing(data.briefing);
    } catch (e) {
      setError(e instanceof Error ? e.message : "Failed");
    } finally {
      setLoading(false);
    }
  }

  return (
    <>
      <PageHeader title="Inbox briefing" description="Calm, action-oriented catch-up — no anxiety, no dumps." />

      <div className="am-section flex gap-3">
        <Button onClick={() => load("daily")} disabled={loading}>
          Daily briefing
        </Button>
        <Button onClick={() => load("weekly")} disabled={loading} variant="secondary">
          Weekly briefing
        </Button>
      </div>

      {error && (
        <Card padding="sm" className="am-section !p-4">
          <p className="am-copy">{error}</p>
        </Card>
      )}

      {briefing && (
        <div className="space-y-8">
          <p className="am-copy">{String(briefing.summary)}</p>
          {Object.entries(briefing).map(([key, value]) => {
            if (key === "summary" || key === "type" || key === "generated_at") return null;
            if (!Array.isArray(value) || !value.length) return null;
            return (
              <Card key={key} padding="md">
                <h2 className="am-title">{key.replace(/_/g, " ")}</h2>
                <ul className="mt-4 space-y-3">
                  {value.slice(0, 5).map((item: Record<string, unknown>, i: number) => (
                    <li key={i} className="am-detail-meta">
                      {String(item.subject ?? item.sender ?? item.rule_name ?? JSON.stringify(item).slice(0, 120))}
                    </li>
                  ))}
                </ul>
              </Card>
            );
          })}
        </div>
      )}
    </>
  );
}
