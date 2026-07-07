"use client";

import { useState } from "react";

type Cadence = "once" | "daily" | "weekly" | "monthly" | "custom";

const CADENCES: { value: Cadence; label: string }[] = [
  { value: "once", label: "Once" },
  { value: "daily", label: "Daily" },
  { value: "weekly", label: "Weekly" },
  { value: "monthly", label: "Monthly" },
  { value: "custom", label: "Custom" },
];

interface AskBoltonBarProps {
  value: string;
  onChange: (value: string) => void;
  onAsk: () => void;
  loading?: boolean;
  onScheduled?: (message: string) => void;
}

/** Dark ask bar — Bolton's stays in his domain: natural-language memory search. */
export function AskBoltonBar({ value, onChange, onAsk, loading, onScheduled }: AskBoltonBarProps) {
  const [showSchedule, setShowSchedule] = useState(false);
  const [cadence, setCadence] = useState<Cadence>("weekly");
  const [customSchedule, setCustomSchedule] = useState("");
  const [scheduling, setScheduling] = useState(false);

  async function handleSchedule() {
    if (!value.trim()) return;
    setScheduling(true);
    try {
      const res = await fetch("/api/schedule", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          prompt: value.trim(),
          cadence,
          custom_schedule: cadence === "custom" ? customSchedule : undefined,
          task_type: "memory_review",
        }),
      });
      const data = await res.json();
      if (!res.ok) throw new Error(data.error ?? "Schedule failed");
      onScheduled?.(data.message);
      setShowSchedule(false);
    } catch (e) {
      onScheduled?.(e instanceof Error ? e.message : "Schedule failed");
    } finally {
      setScheduling(false);
    }
  }

  return (
    <div className="mb-10">
      <div className="am-ask-bar">
        <div className="am-ask-monogram">
          <span className="am-mono-dark">bn</span>
        </div>
        <input
          type="text"
          value={value}
          onChange={(e) => onChange(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === "Enter" && !e.shiftKey) {
              e.preventDefault();
              onAsk();
            }
          }}
          placeholder="Ask Bolton — find anything in memory…"
          className="am-ask-input min-w-0 flex-1 px-4 py-4 text-sm"
          disabled={loading}
        />
        <button
          type="button"
          onClick={onAsk}
          disabled={loading || !value.trim()}
          className="am-ask-action px-5 py-4 text-xs font-bold tracking-[0.15em] uppercase disabled:opacity-40"
        >
          {loading ? "…" : "Ask"}
        </button>
        <button
          type="button"
          onClick={() => setShowSchedule((v) => !v)}
          disabled={!value.trim()}
          className="am-ask-schedule disabled:opacity-40"
        >
          Schedule
        </button>
      </div>

      {showSchedule && (
        <div className="am-card am-card-grain mt-4 p-5">
          <p className="am-label mb-4">cadence · leo calendar</p>
          <div className="flex flex-wrap gap-2">
            {CADENCES.map((c) => (
              <button
                key={c.value}
                type="button"
                onClick={() => setCadence(c.value)}
                className={`am-btn am-copy px-3 py-1.5 text-xs ${
                  cadence === c.value ? "am-btn-primary" : "am-btn-secondary"
                }`}
              >
                {c.label}
              </button>
            ))}
          </div>
          {cadence === "custom" && (
            <input
              type="text"
              value={customSchedule}
              onChange={(e) => setCustomSchedule(e.target.value)}
              placeholder="e.g. every Friday morning"
              className="am-input mt-4 w-full px-4 py-2 text-sm"
            />
          )}
          <button
            type="button"
            onClick={handleSchedule}
            disabled={scheduling || (cadence === "custom" && !customSchedule.trim())}
            className="am-btn am-btn-primary mt-4 px-4 py-2 text-sm"
          >
            {scheduling ? "Saving…" : "Save to Bolton"}
          </button>
        </div>
      )}
    </div>
  );
}
