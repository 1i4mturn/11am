"use client";

import { Button, Card, PageHeader } from "@11am/ui";
import { useState } from "react";

export default function PlanPage() {
  const [plan, setPlan] = useState("");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");
  const [meta, setMeta] = useState<{ events: number; tasks: number } | null>(null);

  async function generate() {
    setLoading(true);
    setError("");
    try {
      const res = await fetch("/api/daily-plan", { method: "POST" });
      const data = await res.json();
      if (!res.ok) throw new Error(data.error);
      setPlan(data.plan);
      setMeta({ events: data.events?.length ?? 0, tasks: data.tasks?.length ?? 0 });
    } catch (e) {
      setError(e instanceof Error ? e.message : "Failed");
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="am-section space-y-6">
      <PageHeader
        title="Daily plan"
        description="Claude synthesises today's calendar and Bolton task entries."
        actions={
          <Button variant="primary" size="sm" onClick={generate} disabled={loading}>
            {loading ? "Generating…" : "Generate plan"}
          </Button>
        }
      />

      {error && <p className="am-copy text-sm text-red-700">{error}</p>}
      {meta && (
        <p className="am-copy text-sm text-[var(--am-muted)]">
          Based on {meta.events} calendar events and {meta.tasks} active tasks
        </p>
      )}

      {plan ? (
        <Card padding="lg">
          <pre className="am-copy whitespace-pre-wrap text-sm">{plan}</pre>
        </Card>
      ) : (
        <Card padding="md">
          <p className="am-copy text-sm text-[var(--am-muted)]">
            Hit generate to build today&apos;s plan from calendar + Bolton tasks.
          </p>
        </Card>
      )}
    </div>
  );
}
