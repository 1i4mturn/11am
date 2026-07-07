"use client";

import { Badge, Button, Card, PageHeader } from "@11am/ui";
import { useCallback, useEffect, useState } from "react";
import { AskColeBar } from "@/components/AskColeBar";
import { MotionTokensPanel } from "@/components/MotionTokensPanel";
import type { BrandSystemDoc, Platform, WorkflowType } from "@/lib/types";

const WORKFLOWS: { value: WorkflowType; label: string; description: string }[] = [
  { value: "script", label: "Script package", description: "Script, shot list, voiceover, editing direction" },
  { value: "concepts", label: "Content concepts", description: "YouTube / Reels / TikTok structure" },
  { value: "storyboard", label: "Storyboard", description: "Text/spec frames only — not rendered video" },
  { value: "transcribe", label: "Transcribe", description: "Whisper API → captions (SRT/VTT)" },
  { value: "convert", label: "Convert", description: "Server-side FFmpeg format optimisation" },
  { value: "motion_template", label: "Motion template", description: "Brand-locked basic template (Robert tokens)" },
];

const DEFAULT_PROMPTS: Record<WorkflowType, string> = {
  script: "60s intro to the 11am agent suite for solo founders — warm, editorial, not hype",
  concepts: "Behind-the-scenes of building LiamOS agents",
  storyboard: "Agent suite walkthrough — William to Marc handoff",
  transcribe: "",
  convert: "",
  motion_template: "",
};

const PLATFORMS: { value: Platform; label: string }[] = [
  { value: "youtube", label: "YouTube" },
  { value: "reels", label: "Reels" },
  { value: "tiktok", label: "TikTok" },
  { value: "general", label: "General" },
];

export default function MotionPage() {
  const [workflow, setWorkflow] = useState<WorkflowType>("script");
  const [query, setQuery] = useState(DEFAULT_PROMPTS.script);
  const [platform, setPlatform] = useState<Platform>("youtube");
  const [brand, setBrand] = useState<BrandSystemDoc | null>(null);
  const [brandMock, setBrandMock] = useState(false);
  const [motionReady, setMotionReady] = useState(false);
  const [result, setResult] = useState<Record<string, unknown> | null>(null);
  const [loading, setLoading] = useState(false);
  const [notice, setNotice] = useState("");
  const [error, setError] = useState("");
  const [mediaFile, setMediaFile] = useState<File | null>(null);
  const [outputFormat, setOutputFormat] = useState<"mp4" | "webm" | "mp3" | "wav">("mp4");
  const [templateId, setTemplateId] = useState("title-reveal");

  const loadBrand = useCallback(async () => {
    const res = await fetch("/api/brand");
    if (res.ok) {
      const data = await res.json();
      setBrand(data.brand_system);
      setBrandMock(data.from_mock ?? false);
      setMotionReady(data.motion_tokens_ready ?? false);
    }
  }, []);

  useEffect(() => {
    loadBrand();
  }, [loadBrand]);

  function selectWorkflow(w: WorkflowType) {
    setWorkflow(w);
    setQuery(DEFAULT_PROMPTS[w]);
    setResult(null);
    setError("");
  }

  async function handleAsk() {
    if (workflow === "transcribe" || workflow === "convert") {
      if (!mediaFile) return;
      setLoading(true);
      setError("");
      setResult(null);
      try {
        const form = new FormData();
        const key = workflow === "transcribe" ? "audio" : "video";
        form.append(key, mediaFile);
        if (workflow === "convert") form.append("output_format", outputFormat);

        const res = await fetch(
          workflow === "transcribe" ? "/api/transcribe" : "/api/convert",
          { method: "POST", body: form }
        );
        const data = await res.json();
        if (!res.ok) throw new Error(data.error);
        setResult(data.result);
      } catch (e) {
        setError(e instanceof Error ? e.message : "Media processing failed");
      } finally {
        setLoading(false);
      }
      return;
    }

    if (workflow === "motion_template") {
      setLoading(true);
      setError("");
      try {
        const res = await fetch("/api/motion-template", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ template_id: templateId }),
        });
        const data = await res.json();
        if (!res.ok) throw new Error(data.error);
        setResult(data.result);
      } catch (e) {
        setError(e instanceof Error ? e.message : "Template failed");
      } finally {
        setLoading(false);
      }
      return;
    }

    if (!query.trim()) return;
    setLoading(true);
    setError("");
    setResult(null);

    const routes: Record<string, string> = {
      script: "/api/script",
      concepts: "/api/concepts",
      storyboard: "/api/storyboard",
    };

    try {
      const body =
        workflow === "script"
          ? { brief: query.trim(), platform }
          : workflow === "concepts"
            ? { topic: query.trim(), platform }
            : { title: query.trim() };

      const res = await fetch(routes[workflow], {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(body),
      });
      const data = await res.json();
      if (!res.ok) throw new Error(data.error);
      setResult(data.result);
    } catch (e) {
      setError(e instanceof Error ? e.message : "Request failed");
    } finally {
      setLoading(false);
    }
  }

  function renderResult() {
    if (!result) return null;
    const r = result as Record<string, unknown>;

    if (workflow === "script") {
      return (
        <Card padding="lg">
          <pre className="am-copy whitespace-pre-wrap text-sm">
            {JSON.stringify(r, null, 2)}
          </pre>
        </Card>
      );
    }

    if (workflow === "transcribe") {
      return (
        <Card padding="lg" className="space-y-4">
          <p className="am-copy text-sm">{String(r.text)}</p>
          <details>
            <summary className="am-label cursor-pointer">SRT captions</summary>
            <pre className="am-copy mt-2 whitespace-pre-wrap text-xs">{String(r.srt)}</pre>
          </details>
        </Card>
      );
    }

    if (workflow === "convert") {
      const url = String(r.download_url ?? "");
      return (
        <Card padding="lg">
          <p className="am-copy mb-4 text-sm">
            Converted to {String(r.output_format)} ·{" "}
            <a href={url} className="underline">
              download
            </a>
          </p>
        </Card>
      );
    }

    if (workflow === "motion_template") {
      return (
        <Card padding="lg">
          <p className="am-label mb-2">preview HTML (brand-locked)</p>
          <pre className="am-copy max-h-96 overflow-auto whitespace-pre-wrap text-xs">
            {String(r.preview_html)}
          </pre>
        </Card>
      );
    }

    return (
      <Card padding="lg">
        <pre className="am-copy whitespace-pre-wrap text-sm">{JSON.stringify(result, null, 2)}</pre>
      </Card>
    );
  }

  const showAskBar = !["transcribe", "convert", "motion_template"].includes(workflow);

  return (
    <div className="am-section space-y-6">
      <PageHeader
        title="Motion"
        description="Scripts, storyboards, and brand-locked motion — grounded in Robert's motion_tokens."
      />

      {brand && (
        <MotionTokensPanel
          doc={brand}
          fromMock={brandMock}
          motionTokensReady={motionReady}
        />
      )}

      <Card padding="md">
        <p className="am-label mb-2">filmed podcast auto-edit — scoped mini-project</p>
        <p className="am-copy text-sm text-[var(--am-muted)]">
          Transcript-driven cuts, chapter markers, and filler removal via a cloud FFmpeg pipeline.
          Cole v1 handles upload/review hooks only — heavy lifting is a separate backend effort, not
          part of this sprint. No CapCut SDK patterns.
        </p>
        <ul className="am-copy mt-3 list-disc space-y-1 pl-5 text-sm text-[var(--am-muted)]">
          <li>Phase 1: Whisper transcript + chapter detection (this app)</li>
          <li>Phase 2: Server worker — FFmpeg cut list from transcript</li>
          <li>Phase 3: Review UI in Cole — approve/reject cuts</li>
        </ul>
      </Card>

      <div className="flex flex-wrap gap-2">
        {WORKFLOWS.map((w) => (
          <button
            key={w.value}
            type="button"
            onClick={() => selectWorkflow(w.value)}
            className={`am-btn am-copy px-3 py-1.5 text-xs ${
              workflow === w.value ? "am-btn-primary" : "am-btn-secondary"
            }`}
          >
            {w.label}
          </button>
        ))}
      </div>

      <p className="am-copy text-sm text-[var(--am-muted)]">
        {WORKFLOWS.find((w) => w.value === workflow)?.description}
      </p>

      {(workflow === "script" || workflow === "concepts") && (
        <div className="flex flex-wrap gap-2">
          {PLATFORMS.map((p) => (
            <button
              key={p.value}
              type="button"
              onClick={() => setPlatform(p.value)}
              className={`am-btn am-copy px-3 py-1.5 text-xs ${
                platform === p.value ? "am-btn-primary" : "am-btn-secondary"
              }`}
            >
              {p.label}
            </button>
          ))}
        </div>
      )}

      {workflow === "motion_template" && (
        <div className="flex flex-wrap gap-2">
          {["title-reveal", "lower-third", "end-card"].map((id) => (
            <button
              key={id}
              type="button"
              onClick={() => setTemplateId(id)}
              className={`am-btn am-copy px-3 py-1.5 text-xs ${
                templateId === id ? "am-btn-primary" : "am-btn-secondary"
              }`}
            >
              {id}
            </button>
          ))}
          <Button variant="primary" size="sm" onClick={handleAsk} disabled={loading || !motionReady}>
            {loading ? "…" : "Render template spec"}
          </Button>
        </div>
      )}

      {(workflow === "transcribe" || workflow === "convert") && (
        <Card padding="md">
          <input
            type="file"
            accept={workflow === "transcribe" ? "audio/*,video/*" : "video/*,audio/*"}
            onChange={(e) => setMediaFile(e.target.files?.[0] ?? null)}
            className="am-copy text-sm"
          />
          {workflow === "convert" && (
            <div className="mt-3 flex flex-wrap gap-2">
              {(["mp4", "webm", "mp3", "wav"] as const).map((f) => (
                <button
                  key={f}
                  type="button"
                  onClick={() => setOutputFormat(f)}
                  className={`am-btn am-copy px-3 py-1.5 text-xs ${
                    outputFormat === f ? "am-btn-primary" : "am-btn-secondary"
                  }`}
                >
                  {f}
                </button>
              ))}
            </div>
          )}
          <Button
            variant="primary"
            size="sm"
            className="mt-4"
            onClick={handleAsk}
            disabled={loading || !mediaFile}
          >
            {loading ? "Processing…" : workflow === "transcribe" ? "Transcribe" : "Convert"}
          </Button>
        </Card>
      )}

      {showAskBar && (
        <AskColeBar
          value={query}
          onChange={setQuery}
          onAsk={handleAsk}
          loading={loading}
          onScheduled={setNotice}
          taskType={workflow === "script" ? "script" : workflow === "concepts" ? "concepts" : workflow === "storyboard" ? "storyboard" : "general"}
        />
      )}

      {notice && <p className="am-copy text-sm">{notice}</p>}
      {error && <p className="am-copy am-error text-sm">{error}</p>}

      {renderResult()}
    </div>
  );
}
