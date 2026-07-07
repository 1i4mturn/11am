"use client";

import { Badge, Button, Card, PageHeader } from "@11am/ui";
import { useCallback, useEffect, useState } from "react";

type TaskCadence = "once" | "daily" | "weekly" | "monthly" | "custom";
type TaskStatus = "pending" | "in_progress" | "done" | "cancelled";
type TaskPriority = "low" | "normal" | "high" | "urgent";

interface BoltonTask {
  id: string;
  title: string;
  summary: string;
  source_agent: string;
  task: {
    status: TaskStatus;
    due_date?: string | null;
    priority: TaskPriority;
    cadence: TaskCadence;
  };
}

const CADENCES: TaskCadence[] = ["once", "daily", "weekly", "monthly", "custom"];
const PRIORITIES: TaskPriority[] = ["low", "normal", "high", "urgent"];

export default function TasksPage() {
  const [tasks, setTasks] = useState<BoltonTask[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const [form, setForm] = useState({
    title: "",
    summary: "",
    priority: "normal" as TaskPriority,
    cadence: "once" as TaskCadence,
    due_date: "",
  });

  const load = useCallback(async () => {
    setLoading(true);
    const res = await fetch("/api/tasks");
    const data = await res.json();
    setTasks(data.tasks ?? []);
    setLoading(false);
  }, []);

  useEffect(() => {
    load();
  }, [load]);

  async function createTask() {
    setError("");
    if (form.summary.length < 10) {
      setError("Summary must be at least 10 characters");
      return;
    }
    try {
      const res = await fetch("/api/tasks", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          title: form.title,
          summary: form.summary,
          source_agent: "Leo",
          priority: form.priority,
          cadence: form.cadence,
          due_date: form.due_date || null,
        }),
      });
      const data = await res.json();
      if (!res.ok) throw new Error(data.error);
      setForm({ title: "", summary: "", priority: "normal", cadence: "once", due_date: "" });
      await load();
    } catch (e) {
      setError(e instanceof Error ? e.message : "Create failed");
    }
  }

  async function updateStatus(id: string, status: TaskStatus) {
    await fetch("/api/tasks", {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ id, status }),
    });
    await load();
  }

  async function removeTask(id: string) {
    await fetch(`/api/tasks?id=${id}`, { method: "DELETE" });
    await load();
  }

  return (
    <div className="am-section space-y-6">
      <PageHeader
        title="Tasks"
        description="Stored as Bolton memory entries (entry_type: task) — visible to all agents."
      />

      {error && <p className="am-copy am-error text-sm">{error}</p>}

      <Card padding="md">
        <p className="am-label mb-3">New task</p>
        <div className="grid gap-3 md:grid-cols-2">
          <input
            className="am-input"
            placeholder="Title"
            value={form.title}
            onChange={(e) => setForm({ ...form, title: e.target.value })}
          />
          <input
            className="am-input"
            type="date"
            value={form.due_date}
            onChange={(e) => setForm({ ...form, due_date: e.target.value })}
          />
          <textarea
            className="am-input md:col-span-2"
            placeholder="Summary (min 10 chars)"
            rows={2}
            value={form.summary}
            onChange={(e) => setForm({ ...form, summary: e.target.value })}
          />
          <select
            className="am-input"
            value={form.priority}
            onChange={(e) => setForm({ ...form, priority: e.target.value as TaskPriority })}
          >
            {PRIORITIES.map((p) => (
              <option key={p} value={p}>{p}</option>
            ))}
          </select>
          <select
            className="am-input"
            value={form.cadence}
            onChange={(e) => setForm({ ...form, cadence: e.target.value as TaskCadence })}
          >
            {CADENCES.map((c) => (
              <option key={c} value={c}>{c}</option>
            ))}
          </select>
        </div>
        <Button variant="secondary" size="sm" className="mt-3" onClick={createTask}>
          Add task
        </Button>
      </Card>

      <Card padding="md">
        <p className="am-label mb-3">Active tasks</p>
        {loading ? (
          <p className="am-copy text-sm">Loading…</p>
        ) : tasks.length ? (
          <ul className="space-y-3">
            {tasks.map((t) => (
              <li key={t.id} className="border-b border-[var(--am-border)] pb-3 last:border-0">
                <div className="flex flex-wrap items-start justify-between gap-2">
                  <div>
                    <p className="am-copy font-medium">{t.title}</p>
                    <p className="am-copy text-sm text-[var(--am-muted)]">{t.summary}</p>
                    <div className="mt-1 flex flex-wrap gap-2">
                      <Badge tone="medium">{t.task.status}</Badge>
                      <Badge tone="low">{t.task.priority}</Badge>
                      <Badge tone="low">{t.task.cadence}</Badge>
                      <span className="am-copy text-xs text-[var(--am-muted)]">{t.source_agent}</span>
                    </div>
                  </div>
                  <div className="flex gap-2">
                    {t.task.status !== "done" && (
                      <Button variant="ghost" size="sm" onClick={() => updateStatus(t.id, "done")}>
                        Done
                      </Button>
                    )}
                    <Button variant="ghost" size="sm" onClick={() => removeTask(t.id)}>
                      Archive
                    </Button>
                  </div>
                </div>
              </li>
            ))}
          </ul>
        ) : (
          <p className="am-copy text-sm text-[var(--am-muted)]">No tasks in Bolton yet.</p>
        )}
      </Card>
    </div>
  );
}
