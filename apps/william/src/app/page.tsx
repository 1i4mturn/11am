"use client";

import { useEffect, useState } from "react";
import { Button, Card, PageHeader } from "@11am/ui";
import { AskWilliamBar } from "@/components/AskWilliamBar";

const PLATFORMS = [
  { value: "email", label: "Email" },
  { value: "linkedin", label: "LinkedIn" },
  { value: "blog", label: "Blog" },
  { value: "slack", label: "Slack" },
  { value: "announcement", label: "Announcement" },
  { value: "other", label: "Other" },
] as const;

type Platform = (typeof PLATFORMS)[number]["value"];

interface RobertHandoff {
  copy: string;
  platform: string;
  format: string;
  tone_notes: string;
  visual_direction: string;
}

const HANDOFF_FIELDS: { key: keyof RobertHandoff; label: string }[] = [
  { key: "copy", label: "copy" },
  { key: "platform", label: "platform" },
  { key: "format", label: "format" },
  { key: "tone_notes", label: "tone notes" },
  { key: "visual_direction", label: "visual direction" },
];

function parseSseEvents(buffer: string): { events: Array<{ event: string; data: string }>; rest: string } {
  const events: Array<{ event: string; data: string }> = [];
  const parts = buffer.split("\n\n");
  const rest = parts.pop() ?? "";

  for (const part of parts) {
    if (!part.trim()) continue;
    let event = "message";
    let data = "";
    for (const line of part.split("\n")) {
      if (line.startsWith("event: ")) event = line.slice(7);
      if (line.startsWith("data: ")) data = line.slice(6);
    }
    if (data) events.push({ event, data });
  }

  return { events, rest };
}

export default function WritePage() {
  const [prompt, setPrompt] = useState("");
  const [context, setContext] = useState("");
  const [platform, setPlatform] = useState<Platform>("email");
  const [includeBusinessContext, setIncludeBusinessContext] = useState(false);
  const [output, setOutput] = useState("");
  const [editedOutput, setEditedOutput] = useState("");
  const [generationId, setGenerationId] = useState<string | null>(null);
  const [confidence, setConfidence] = useState<number | null>(null);
  const [loading, setLoading] = useState(false);
  const [savingEdit, setSavingEdit] = useState(false);
  const [error, setError] = useState("");
  const [notice, setNotice] = useState("");
  const [sampleCount, setSampleCount] = useState(0);
  const [handoff, setHandoff] = useState<RobertHandoff | null>(null);
  const [showHandoff, setShowHandoff] = useState(false);

  useEffect(() => {
    fetch("/api/voice-profile")
      .then((r) => r.json())
      .then((data) => setSampleCount(data.sampleCount ?? 0))
      .catch(() => {});
  }, []);

  async function handleGenerate() {
    if (!prompt.trim()) return;
    setLoading(true);
    setError("");
    setNotice("");
    setHandoff(null);
    setShowHandoff(false);
    setOutput("");
    setEditedOutput("");

    try {
      const res = await fetch("/api/generate/stream", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          prompt,
          platform,
          context: context || undefined,
          includeBusinessContext,
        }),
      });

      if (!res.ok || !res.body) {
        const data = await res.json().catch(() => ({}));
        throw new Error(data.error ?? "Generation failed");
      }

      const reader = res.body.getReader();
      const decoder = new TextDecoder();
      let buffer = "";
      let streamed = "";

      while (true) {
        const { done, value } = await reader.read();
        if (done) break;
        buffer += decoder.decode(value, { stream: true });

        const { events, rest } = parseSseEvents(buffer);
        buffer = rest;

        for (const { event, data } of events) {
          const parsed = JSON.parse(data) as Record<string, unknown>;
          if (event === "delta" && typeof parsed.text === "string") {
            streamed += parsed.text;
            setEditedOutput(streamed);
          }
          if (event === "error") {
            throw new Error(String(parsed.error ?? "Generation failed"));
          }
          if (event === "done") {
            setOutput(String(parsed.output ?? streamed));
            setEditedOutput(String(parsed.output ?? streamed));
            setGenerationId(String(parsed.id));
            setConfidence(Number(parsed.confidence));
            setHandoff(parsed.handoff as RobertHandoff);
          }
        }
      }
    } catch (e) {
      setError(e instanceof Error ? e.message : "Something went wrong");
    } finally {
      setLoading(false);
    }
  }

  async function handleSaveEdit() {
    if (!generationId || editedOutput === output) return;
    setSavingEdit(true);
    try {
      const res = await fetch("/api/edits", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ generationId, editedOutput }),
      });
      const data = await res.json();
      if (!res.ok) throw new Error(data.error ?? "Failed to save edit");
      setOutput(editedOutput);
      setNotice("Edit saved - William learned from your changes.");
    } catch (e) {
      setError(e instanceof Error ? e.message : "Failed to save edit");
    } finally {
      setSavingEdit(false);
    }
  }

  return (
    <>
      <PageHeader
        title="Write in your voice"
        description="William produces copy-ready drafts - warm, clear, authentically you."
        meta={
          sampleCount > 0
            ? `${sampleCount} writing samples in your voice profile`
            : "Add writing samples in Voice setup to sharpen your profile"
        }
      />

      <AskWilliamBar
        value={prompt}
        onChange={setPrompt}
        onAsk={handleGenerate}
        loading={loading}
        platform={platform}
        includeBusinessContext={includeBusinessContext}
        onScheduled={(msg) => setNotice(msg)}
      />

      {notice && (
        <Card padding="sm" className="mb-6 !p-4">
          <p className="am-copy">{notice}</p>
        </Card>
      )}

      <div className="grid gap-12 lg:grid-cols-2">
        <div className="space-y-8">
          <div>
            <p className="am-label mb-3">platform</p>
            <div className="flex flex-wrap gap-2">
              {PLATFORMS.map((p) => (
                <button
                  key={p.value}
                  type="button"
                  onClick={() => setPlatform(p.value)}
                  className={`am-btn am-copy px-3 py-1.5 ${
                    platform === p.value ? "am-btn-primary" : "am-btn-secondary"
                  }`}
                >
                  {p.label}
                </button>
              ))}
            </div>
          </div>

          <div>
            <p className="am-label mb-3">
              context <span className="normal-case tracking-normal">(optional)</span>
            </p>
            <textarea
              value={context}
              onChange={(e) => setContext(e.target.value)}
              placeholder="Paste notes, a brief, or raw thoughts for William to shape"
              rows={3}
              className="am-input am-copy w-full px-4 py-3"
            />
          </div>

          <label className="flex items-center gap-2 am-copy">
            <input
              type="checkbox"
              checked={includeBusinessContext}
              onChange={(e) => setIncludeBusinessContext(e.target.checked)}
            />
            Include business context from George & Conner (Bolton)
          </label>

          {error && (
            <Card padding="sm" className="!p-4">
              <p className="am-copy">{error}</p>
            </Card>
          )}
        </div>

        <div className="space-y-8">
          <div className="flex items-center justify-between">
            <p className="am-label">output</p>
            {confidence !== null && (
              <div className="flex items-center gap-2">
                <div className="h-1.5 w-24 overflow-hidden bg-border">
                  <div
                    className="h-full bg-foreground transition-all"
                    style={{ width: `${confidence}%` }}
                  />
                </div>
                <span className="am-label">{confidence}% match</span>
              </div>
            )}
          </div>

          <textarea
            value={editedOutput}
            onChange={(e) => setEditedOutput(e.target.value)}
            placeholder="Your copy will stream here…"
            rows={16}
            className="am-input am-copy w-full px-4 py-3 leading-relaxed"
          />

          {output && editedOutput !== output && (
            <Button onClick={handleSaveEdit} disabled={savingEdit} variant="secondary">
              {savingEdit ? "Saving…" : "Save edit - teach William your voice"}
            </Button>
          )}

          {handoff && (
            <Card padding="lg" className="!p-6">
              <button
                type="button"
                onClick={() => setShowHandoff((v) => !v)}
                className="flex w-full items-center justify-between"
              >
                <span className="am-title">hand off to robert</span>
                <span className="am-label">{showHandoff ? "hide" : "show"}</span>
              </button>
              {showHandoff && (
                <div className="mt-6 space-y-5">
                  {HANDOFF_FIELDS.map(({ key, label }) => (
                    <div key={key} className="flex gap-6">
                      <span className="am-bracket-label">[ {label} ]</span>
                      <p className="am-field-value flex-1 whitespace-pre-wrap">{handoff[key]}</p>
                    </div>
                  ))}
                  <Button
                    type="button"
                    variant="ghost"
                    size="sm"
                    onClick={() => {
                      navigator.clipboard.writeText(JSON.stringify(handoff, null, 2));
                      setNotice("Robert handoff JSON copied.");
                    }}
                  >
                    Copy JSON for Robert
                  </Button>
                </div>
              )}
            </Card>
          )}
        </div>
      </div>
    </>
  );
}
