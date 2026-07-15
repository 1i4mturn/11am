"use client";

import { useEffect, useState, useCallback, Suspense } from "react";
import { useSearchParams } from "next/navigation";
import { Button, Card, PageHeader } from "@11am/ui";

function SetupContent() {
  const searchParams = useSearchParams();
  const [pasteText, setPasteText] = useState("");
  const [url, setUrl] = useState("");
  const [loading, setLoading] = useState(false);
  const [message, setMessage] = useState("");
  const [error, setError] = useState("");
  const [profile, setProfile] = useState<string | null>(null);
  const [tier, setTier] = useState("free");
  const [gmailStatus, setGmailStatus] = useState<{
    connected: boolean;
    needsReauth?: boolean;
    daysUntilExpiry?: number | null;
    authUrl: string | null;
    message?: string;
  } | null>(null);
  const [sampleCount, setSampleCount] = useState(0);

  const loadProfile = useCallback(async () => {
    const res = await fetch("/api/voice-profile");
    const data = await res.json();
    setTier(data.tier);
    setProfile(data.profile?.profileMarkdown ?? null);
    setSampleCount(data.sampleCount ?? 0);
  }, []);

  useEffect(() => {
    loadProfile();
  }, [loadProfile]);

  useEffect(() => {
    const gmail = searchParams.get("gmail");
    if (gmail === "connected") setMessage("Gmail connected successfully.");
    if (gmail === "error") setError("Gmail connection failed.");
  }, [searchParams]);

  useEffect(() => {
    fetch("/api/gmail")
      .then((r) => r.json())
      .then(setGmailStatus)
      .catch(() => {});
  }, [tier]);

  async function ingest(body: FormData | object) {
    setLoading(true);
    setError("");
    setMessage("");

    try {
      const isForm = body instanceof FormData;
      const res = await fetch("/api/ingest", {
        method: "POST",
        ...(isForm ? { body } : { headers: { "Content-Type": "application/json" }, body: JSON.stringify(body) }),
      });
      const data = await res.json();
      if (!res.ok) throw new Error(data.error ?? "Ingestion failed");
      setMessage(`Ingested ${data.chars?.toLocaleString() ?? ""} characters (${data.chunksAdded} chunks). Profile updating…`);
      await loadProfile();
    } catch (e) {
      setError(e instanceof Error ? e.message : "Ingestion failed");
    } finally {
      setLoading(false);
    }
  }

  async function handlePasteSubmit() {
    if (pasteText.length < 50) {
      setError("Please provide at least 50 characters of writing.");
      return;
    }
    await ingest({ text: pasteText });
  }

  async function handleUrlSubmit() {
    if (!url.trim()) return;
    const form = new FormData();
    form.append("url", url);
    await ingest(form);
  }

  async function handleFileUpload(e: React.ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0];
    if (!file) return;
    const form = new FormData();
    form.append("file", file);
    await ingest(form);
  }

  async function syncGmail() {
    setLoading(true);
    setError("");
    try {
      const res = await fetch("/api/gmail", { method: "POST" });
      const data = await res.json();
      if (!res.ok) throw new Error(data.error ?? "Gmail sync failed");
      setMessage(`Synced ${data.emailsIngested} sent emails (${data.chunksAdded} chunks).`);
      await loadProfile();
    } catch (e) {
      setError(e instanceof Error ? e.message : "Gmail sync failed");
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="max-w-3xl">
      <PageHeader
        title="Build your voice profile"
        description="Feed William your real writing. He analyses your corpus and stores your voice in Bolton."
      />

      {profile && (
        <Card className="am-section" padding="md">
          <div className="mb-4 flex items-center justify-between">
            <h2 className="am-title">current voice profile</h2>
            <span className="am-label">{sampleCount} writing samples</span>
          </div>
          <p className="am-copy max-h-48 overflow-auto whitespace-pre-wrap leading-relaxed">{profile}</p>
        </Card>
      )}

      {message && (
        <Card padding="sm" className="am-section !p-4">
          <p className="am-copy">{message}</p>
        </Card>
      )}
      {error && (
        <Card padding="sm" className="am-section !p-4">
          <p className="am-copy">{error}</p>
        </Card>
      )}

      <div className="space-y-8">
        <Card padding="lg">
          <h2 className="am-title">gmail - highest value source</h2>
          <p className="am-detail-meta mt-2">
            Sent emails are the richest training data. William pulls your sent mail only.
          </p>
          <div className="mt-6 flex flex-wrap gap-3">
            {gmailStatus?.needsReauth && gmailStatus.authUrl && (
              <Card padding="sm" className="mb-4 w-full !p-4">
                <p className="am-copy">
                  Gmail Testing mode - refresh token expires every 7 days.
                  {gmailStatus.daysUntilExpiry !== null && gmailStatus.daysUntilExpiry !== undefined
                    ? ` ~${gmailStatus.daysUntilExpiry} day(s) left.`
                    : " Reconnect now."}
                </p>
                <a
                  href={gmailStatus.authUrl}
                  className="am-btn am-btn-primary am-copy mt-3 inline-flex px-4 py-2"
                >
                  Reconnect Gmail
                </a>
              </Card>
            )}
            {gmailStatus?.connected && !gmailStatus.needsReauth ? (
              <Button onClick={syncGmail} disabled={loading}>
                Sync sent emails
              </Button>
            ) : gmailStatus?.authUrl ? (
              <a href={gmailStatus.authUrl} className="am-btn am-btn-primary am-copy inline-flex px-4 py-2">
                Connect Gmail
              </a>
            ) : (
              <p className="am-detail-meta">{gmailStatus?.message ?? "Loading Gmail status…"}</p>
            )}
          </div>
        </Card>

        <Card padding="lg">
          <h2 className="am-title">paste writing</h2>
          <textarea
            value={pasteText}
            onChange={(e) => setPasteText(e.target.value)}
            placeholder="Paste emails, posts, documents - anything you've written"
            rows={6}
            className="am-input am-copy mt-4 w-full px-4 py-3"
          />
          <Button onClick={handlePasteSubmit} disabled={loading} variant="secondary" className="mt-4">
            Analyse & ingest
          </Button>
        </Card>

        <Card padding="lg">
          <h2 className="am-title">upload file</h2>
          <p className="am-detail-meta mt-2">.txt, .md, .docx, .pdf (text-based)</p>
          <input
            type="file"
            accept=".txt,.md,.docx,.pdf"
            onChange={handleFileUpload}
            disabled={loading}
            className="am-copy mt-4 block"
          />
        </Card>

        <Card padding="lg">
          <h2 className="am-title">import from url</h2>
          <div className="mt-4 flex gap-3">
            <input
              type="url"
              value={url}
              onChange={(e) => setUrl(e.target.value)}
              placeholder="https://…"
              className="am-input am-copy flex-1 px-4 py-2"
            />
            <Button onClick={handleUrlSubmit} disabled={loading || !url.trim()} variant="secondary">
              Fetch
            </Button>
          </div>
        </Card>
      </div>
    </div>
  );
}

export default function SetupPage() {
  return (
    <Suspense fallback={<div className="p-10 text-center am-copy">Loading…</div>}>
      <SetupContent />
    </Suspense>
  );
}
