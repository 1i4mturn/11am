"use client";

import { Badge, Button, Card } from "@11am/ui";
import { useCallback, useEffect, useState } from "react";

interface JobRecord {
  id: string;
  status: string;
  stage: string;
  progress: number;
  prompt: string;
  cost: {
    input_tokens: number;
    output_tokens: number;
    estimated_usd: number;
    elapsed_ms: number;
  };
  budget: {
    max_tokens: number;
    max_time_ms: number;
    max_cost_usd: number;
  };
  steps: Array<{ id: string; label: string; status: string; detail?: string }>;
  error?: string;
  result?: Record<string, unknown>;
}

interface JobMonitorProps {
  selectedJobId?: string | null;
  onSelectJob?: (id: string) => void;
}

export function JobMonitor({ selectedJobId, onSelectJob }: JobMonitorProps) {
  const [jobs, setJobs] = useState<JobRecord[]>([]);
  const [active, setActive] = useState<JobRecord | null>(null);
  const [pushNotice, setPushNotice] = useState("");

  const loadJobs = useCallback(async () => {
    const res = await fetch("/api/jobs");
    if (res.ok) {
      const data = await res.json();
      setJobs(data.jobs ?? []);
    }
  }, []);

  useEffect(() => {
    loadJobs();
    const interval = setInterval(loadJobs, 5000);
    return () => clearInterval(interval);
  }, [loadJobs]);

  useEffect(() => {
    const id = selectedJobId ?? jobs[0]?.id;
    if (!id) return;

    const es = new EventSource(`/api/jobs/${id}/events`);
    es.onmessage = (ev) => {
      try {
        const data = JSON.parse(ev.data);
        if (data.job) setActive(data.job);
        if (data.type === "completed" || data.type === "failed" || data.type === "killed") {
          setPushNotice(`Job ${data.type}: ${data.message ?? data.stage ?? ""}`);
          loadJobs();
        }
      } catch {
        // ignore
      }
    };
    return () => es.close();
  }, [selectedJobId, jobs, loadJobs]);

  async function handleKill(id: string) {
    await fetch(`/api/jobs/${id}`, { method: "DELETE" });
    loadJobs();
  }

  async function subscribePush(jobId: string) {
    const endpoint = `${window.location.origin}/api/push/inbox`;
    await fetch("/api/push/subscribe", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ job_id: jobId, endpoint }),
    });
    setPushNotice("Push subscription registered for job completion");
  }

  const display = active ?? jobs.find((j) => j.id === selectedJobId) ?? jobs[0];

  return (
    <Card padding="lg" className="space-y-6">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div>
          <p className="am-label">job monitor · suite-wide queue</p>
          <p className="am-copy text-sm text-[var(--am-muted)]">
            Reusable by Leo (orchestration) and Cole (video pipeline)
          </p>
        </div>
        <Button variant="secondary" size="sm" onClick={loadJobs}>
          Refresh
        </Button>
      </div>

      <div className="flex flex-wrap gap-2">
        {jobs.slice(0, 8).map((j) => (
          <button
            key={j.id}
            type="button"
            onClick={() => onSelectJob?.(j.id)}
            className={`am-btn am-copy px-3 py-1.5 text-xs ${
              display?.id === j.id ? "am-btn-primary" : "am-btn-secondary"
            }`}
          >
            {j.status} · {j.prompt.slice(0, 24)}…
          </button>
        ))}
      </div>

      {display && (
        <div className="space-y-4">
          <div className="flex flex-wrap items-center gap-2">
            <Badge
              tone={
                display.status === "completed"
                  ? "high"
                  : display.status === "failed" || display.status === "killed"
                    ? "medium"
                    : "low"
              }
            >
              {display.status}
            </Badge>
            <span className="am-copy text-sm">{display.stage}</span>
          </div>

          <div className="h-2 w-full overflow-hidden rounded bg-[var(--am-border)]">
            <div
              className="h-full bg-[var(--am-ink)] transition-all"
              style={{ width: `${display.progress}%` }}
            />
          </div>

          <div className="grid gap-4 md:grid-cols-3">
            <BudgetCard label="tokens" value={`${display.cost.input_tokens + display.cost.output_tokens} / ${display.budget.max_tokens}`} />
            <BudgetCard label="cost est." value={`$${display.cost.estimated_usd.toFixed(3)} / $${display.budget.max_cost_usd}`} />
            <BudgetCard label="time" value={`${Math.round(display.cost.elapsed_ms / 1000)}s / ${Math.round(display.budget.max_time_ms / 1000)}s`} />
          </div>

          <ul className="am-copy space-y-2 text-sm">
            {display.steps.map((s) => (
              <li key={s.id} className="flex items-start gap-2">
                <span className="font-mono text-xs text-[var(--am-muted)]">{s.status}</span>
                <span>{s.label}</span>
                {s.detail && (
                  <span className="text-[var(--am-muted)]">— {s.detail.slice(0, 80)}</span>
                )}
              </li>
            ))}
          </ul>

          <div className="flex flex-wrap gap-2">
            {(display.status === "running" || display.status === "queued") && (
              <Button variant="secondary" size="sm" onClick={() => handleKill(display.id)}>
                Kill switch
              </Button>
            )}
            <Button variant="secondary" size="sm" onClick={() => subscribePush(display.id)}>
              Notify on complete
            </Button>
          </div>

          {display.error && (
            <p className="am-copy text-sm text-red-700">{display.error}</p>
          )}

          {display.result && (
            <details>
              <summary className="am-label cursor-pointer">Job result</summary>
              <pre className="am-copy mt-2 max-h-64 overflow-auto whitespace-pre-wrap text-xs">
                {JSON.stringify(display.result, null, 2)}
              </pre>
            </details>
          )}
        </div>
      )}

      {pushNotice && <p className="am-copy text-sm">{pushNotice}</p>}
    </Card>
  );
}

function BudgetCard({ label, value }: { label: string; value: string }) {
  return (
    <div className="am-card am-card-grain p-4">
      <p className="am-label mb-1">{label}</p>
      <p className="am-copy text-sm font-mono">{value}</p>
    </div>
  );
}
