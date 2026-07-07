"use client";

import { Badge, Button, Card, PageHeader } from "@11am/ui";
import { useCallback, useEffect, useState } from "react";

interface Report {
  agent_id: string;
  available: boolean;
  context_pack?: {
    task: string;
    relevant_memory: Array<{
      title: string;
      summary: string;
      source_agent: string;
      entry_type: string;
    }>;
    active_decisions: string[];
    warnings: string[];
  } | null;
}

export default function ReportsPage() {
  const [reports, setReports] = useState<Report[]>([]);
  const [opsSummary, setOpsSummary] = useState("");
  const [loading, setLoading] = useState(true);
  const [opsLoading, setOpsLoading] = useState(false);
  const [error, setError] = useState("");

  const load = useCallback(async () => {
    setLoading(true);
    const res = await fetch("/api/reports");
    const data = await res.json();
    setReports(data.reports ?? []);
    setLoading(false);
  }, []);

  useEffect(() => {
    load();
  }, [load]);

  async function runOpsSummary(period: "weekly" | "monthly") {
    setOpsLoading(true);
    setError("");
    try {
      const res = await fetch(`/api/ops-summary?period=${period}`);
      const data = await res.json();
      if (!res.ok) throw new Error(data.error);
      setOpsSummary(data.summary);
    } catch (e) {
      setError(e instanceof Error ? e.message : "Ops summary failed");
    } finally {
      setOpsLoading(false);
    }
  }

  return (
    <div className="am-section space-y-6">
      <PageHeader
        title="Reporting"
        description="George, James, and Conner summaries via Bolton context-pack. Ops summaries over Bolton entries."
        actions={
          <div className="flex gap-2">
            <Button variant="secondary" size="sm" onClick={() => runOpsSummary("weekly")} disabled={opsLoading}>
              Weekly ops
            </Button>
            <Button variant="secondary" size="sm" onClick={() => runOpsSummary("monthly")} disabled={opsLoading}>
              Monthly ops
            </Button>
          </div>
        }
      />

      {error && <p className="am-copy am-error text-sm">{error}</p>}

      {loading ? (
        <p className="am-copy text-sm">Loading reports…</p>
      ) : (
        <div className="grid gap-4 md:grid-cols-3">
          {reports.map((r) => (
            <Card key={r.agent_id} padding="md">
              <div className="mb-3 flex items-center gap-2">
                <p className="am-label capitalize">{r.agent_id}</p>
                <Badge tone={r.available ? "high" : "low"}>
                  {r.available ? "Live" : "No data"}
                </Badge>
              </div>
              {r.context_pack ? (
                <div className="space-y-2">
                  <p className="am-copy text-xs text-[var(--am-muted)]">{r.context_pack.task}</p>
                  {r.context_pack.relevant_memory.slice(0, 3).map((m, i) => (
                    <div key={i} className="border-t border-[var(--am-border)] pt-2">
                      <p className="am-copy text-sm font-medium">{m.title}</p>
                      <p className="am-copy text-xs text-[var(--am-muted)]">{m.summary}</p>
                    </div>
                  ))}
                  {r.context_pack.active_decisions.length > 0 && (
                    <div className="mt-2">
                      <p className="am-label text-xs">Decisions</p>
                      <ul className="am-copy text-xs">
                        {r.context_pack.active_decisions.slice(0, 2).map((d, i) => (
                          <li key={i}>{d}</li>
                        ))}
                      </ul>
                    </div>
                  )}
                </div>
              ) : (
                <p className="am-copy text-sm text-[var(--am-muted)]">No context pack returned.</p>
              )}
            </Card>
          ))}
        </div>
      )}

      {opsSummary && (
        <Card padding="lg">
          <p className="am-label mb-3">Ops summary</p>
          <pre className="am-copy whitespace-pre-wrap text-sm">{opsSummary}</pre>
        </Card>
      )}
    </div>
  );
}
