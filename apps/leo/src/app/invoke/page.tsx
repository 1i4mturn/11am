"use client";

import { Badge, Button, Card, PageHeader } from "@11am/ui";
import { useState } from "react";

const AGENTS = ["james", "george", "conner", "william", "marc", "bolton", "robert", "johnny"];

interface InvokeResponse {
  from_agent: string;
  to_agent: string;
  summary: string;
  structured_result?: Record<string, unknown>;
  memory_ids_written: string[];
  follow_up_needed: boolean;
  error?: string;
}

export default function InvokePage() {
  const [toAgent, setToAgent] = useState("james");
  const [task, setTask] = useState(
    "Compare voice-fidelity tools for solo founders - differentiation vs generic AI writing assistants"
  );
  const [priority, setPriority] = useState<"normal" | "urgent">("normal");
  const [loading, setLoading] = useState(false);
  const [response, setResponse] = useState<InvokeResponse | null>(null);
  const [error, setError] = useState("");

  async function invoke() {
    setLoading(true);
    setError("");
    setResponse(null);
    try {
      const res = await fetch("/api/invoke", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          from_agent: "leo",
          to_agent: toAgent,
          task,
          priority,
          response_mode: "sync",
        }),
      });
      const data = await res.json();
      if (!res.ok) throw new Error(data.error);
      setResponse(data);
    } catch (e) {
      setError(e instanceof Error ? e.message : "Invoke failed");
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="am-section space-y-6">
      <PageHeader
        title="Route agent"
        description="Shared agent-invocation contract - v1 synchronous, one agent at a time."
      />

      <Card padding="md">
        <p className="am-label mb-3">Invocation request</p>
        <div className="grid gap-3">
          <div className="flex gap-4">
            <label className="am-copy text-sm">
              From: <strong>leo</strong>
            </label>
            <label className="am-copy text-sm">
              To:
              <select
                className="am-input ml-2"
                value={toAgent}
                onChange={(e) => setToAgent(e.target.value)}
              >
                {AGENTS.map((a) => (
                  <option key={a} value={a}>{a}</option>
                ))}
              </select>
            </label>
            <label className="am-copy text-sm">
              Priority:
              <select
                className="am-input ml-2"
                value={priority}
                onChange={(e) => setPriority(e.target.value as "normal" | "urgent")}
              >
                <option value="normal">normal</option>
                <option value="urgent">urgent</option>
              </select>
            </label>
          </div>
          <textarea
            className="am-input"
            rows={4}
            value={task}
            onChange={(e) => setTask(e.target.value)}
          />
          <Button variant="primary" size="sm" onClick={invoke} disabled={loading || !task.trim()}>
            {loading ? "Routing…" : `Invoke ${toAgent}`}
          </Button>
        </div>
      </Card>

      {error && <p className="am-copy am-error text-sm">{error}</p>}

      {response && (
        <Card padding="lg">
          <div className="mb-3 flex flex-wrap gap-2">
            <Badge tone="high">{response.from_agent} → {response.to_agent}</Badge>
            {response.follow_up_needed && <Badge tone="low">Follow-up needed</Badge>}
            {response.memory_ids_written.length > 0 && (
              <Badge tone="medium">Saved to Bolton</Badge>
            )}
          </div>
          <p className="am-copy whitespace-pre-wrap text-sm">{response.summary}</p>
          {response.structured_result && (
            <pre className="am-copy mt-4 whitespace-pre-wrap rounded border border-[var(--am-border)] p-3 text-xs">
              {JSON.stringify(response.structured_result, null, 2)}
            </pre>
          )}
        </Card>
      )}

      <Card padding="md">
        <p className="am-label mb-2">Contract (v1)</p>
        <pre className="am-copy text-xs text-[var(--am-muted)]">
{`request: { from_agent, to_agent, task, context_ref?, priority, response_mode }
response: { from_agent, to_agent, summary, structured_result?, memory_ids_written, follow_up_needed }`}
        </pre>
      </Card>
    </div>
  );
}
