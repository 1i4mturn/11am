"use client";

import { Badge, Button, Card, PageHeader } from "@11am/ui";
import { Suspense, useCallback, useEffect, useState } from "react";
import { useSearchParams } from "next/navigation";
import { AskMarcBar } from "@/components/AskMarcBar";

interface TriageItem {
  message_id: string;
  thread_id: string;
  sender: string;
  sender_email: string;
  subject: string;
  why_it_matters: string;
  priority: "high" | "medium" | "low";
  classification: string;
  suggested_action: string;
  suggested_reply?: string;
  handoff_agent?: string;
}

interface SearchResult {
  message_id: string;
  sender: string;
  subject: string;
  why_matched: string;
  suggested_action: string;
}

interface GmailStatus {
  connected: boolean;
  needsReauth?: boolean;
  daysUntilExpiry?: number | null;
  authUrl: string | null;
  indexedCount: number;
  lastSyncAt?: string;
  message?: string;
}

function InboxContent() {
  const searchParams = useSearchParams();
  const [askQuery, setAskQuery] = useState("");
  const [items, setItems] = useState<TriageItem[]>([]);
  const [searchResults, setSearchResults] = useState<SearchResult[]>([]);
  const [gmail, setGmail] = useState<GmailStatus | null>(null);
  const [loading, setLoading] = useState(false);
  const [searching, setSearching] = useState(false);
  const [syncing, setSyncing] = useState(false);
  const [error, setError] = useState("");
  const [notice, setNotice] = useState("");
  const [expandedReply, setExpandedReply] = useState<string | null>(null);
  const [drafts, setDrafts] = useState<Record<string, string>>({});
  const [williamHandoffs, setWilliamHandoffs] = useState<Record<string, string>>({});

  const loadGmail = useCallback(async () => {
    const res = await fetch("/api/gmail");
    setGmail(await res.json());
  }, []);

  useEffect(() => {
    loadGmail();
  }, [loadGmail]);

  useEffect(() => {
    const g = searchParams.get("gmail");
    if (g === "connected") setNotice("Gmail connected. Sync your inbox to begin.");
    if (g === "error") setError("Gmail connection failed.");
  }, [searchParams]);

  async function syncInbox() {
    setSyncing(true);
    setError("");
    try {
      const res = await fetch("/api/gmail", { method: "POST" });
      const data = await res.json();
      if (!res.ok) throw new Error(data.error);
      setNotice(`Synced ${data.newMessages} new messages.`);
      await loadGmail();
    } catch (e) {
      setError(e instanceof Error ? e.message : "Sync failed");
    } finally {
      setSyncing(false);
    }
  }

  async function runTriage() {
    setLoading(true);
    setError("");
    setSearchResults([]);
    try {
      const res = await fetch("/api/triage", { method: "POST" });
      const data = await res.json();
      if (!res.ok) throw new Error(data.error);
      setItems(data.items);
    } catch (e) {
      setError(e instanceof Error ? e.message : "Triage failed");
    } finally {
      setLoading(false);
    }
  }

  async function handleAsk() {
    if (!askQuery.trim()) return;
    setSearching(true);
    setError("");
    setSearchResults([]);
    try {
      const res = await fetch("/api/search", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ query: askQuery.trim() }),
      });
      const data = await res.json();
      if (!res.ok) throw new Error(data.error);
      setSearchResults(data.results ?? []);
      if (!data.results?.length) setNotice("No matches — try syncing first or rephrase your query.");
    } catch (e) {
      setError(e instanceof Error ? e.message : "Search failed");
    } finally {
      setSearching(false);
    }
  }

  async function draftReply(messageId: string, handoffToWilliam = false) {
    setExpandedReply(messageId);
    try {
      const res = await fetch("/api/replies/draft", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ messageId, handoffToWilliam }),
      });
      const data = await res.json();
      if (!res.ok) throw new Error(data.error);
      setDrafts((d) => ({ ...d, [messageId]: data.brief.draft_reply }));
      if (data.handoffId) {
        setWilliamHandoffs((h) => ({ ...h, [messageId]: data.handoffId }));
        setNotice("High-stakes reply handed off to William for polish.");
      }
    } catch (e) {
      setError(e instanceof Error ? e.message : "Draft failed");
    }
  }

  async function confirmArchive(messageId: string) {
    if (!confirm("Archive this message in Gmail?")) return;
    const res = await fetch("/api/actions", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ action: "archive", messageIds: [messageId], confirmed: true }),
    });
    if (res.ok) setItems((items) => items.filter((i) => i.message_id !== messageId));
  }

  async function saveDraft(messageId: string, threadId: string) {
    const body = drafts[messageId];
    if (!body) return;
    const res = await fetch("/api/actions", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        action: "draft",
        messageIds: [messageId],
        threadId,
        replyBody: body,
        confirmed: true,
      }),
    });
    const data = await res.json();
    if (res.ok) setNotice(`Draft saved in Gmail (${data.draftId})`);
    else setError(data.error);
  }

  async function handoff(messageId: string, agent: string, item: TriageItem) {
    const res = await fetch("/api/handoffs", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        targetAgent: agent,
        sourceMessageId: messageId,
        item: { ...item, thread_id: item.thread_id },
      }),
    });
    const data = await res.json();
    if (res.ok) setNotice(`Handed off to ${agent} (${data.handoff.id.slice(0, 8)}…)`);
    else setError(data.error);
  }

  const priorityTone = { high: "high" as const, medium: "medium" as const, low: "low" as const };

  return (
    <>
      <PageHeader
        title="Inbox intelligence"
        description="Marc triages your Gmail — relationship context, not another email client."
      />

      <AskMarcBar
        value={askQuery}
        onChange={setAskQuery}
        onAsk={handleAsk}
        loading={searching}
        taskType="search"
        onScheduled={(msg) => setNotice(msg)}
      />

      {notice && (
        <Card padding="sm" className="am-section !p-4">
          <p className="am-copy">{notice}</p>
        </Card>
      )}
      {error && (
        <Card padding="sm" className="am-section !p-4">
          <p className="am-copy">{error}</p>
        </Card>
      )}

      <Card className="am-section" padding="lg">
        <h2 className="am-title">gmail connection</h2>
        {gmail?.needsReauth && gmail.authUrl && (
          <Card padding="sm" className="mt-4 !p-4">
            <p className="am-copy">
              Gmail Testing mode — refresh token expires every 7 days.
              {gmail.daysUntilExpiry != null ? ` ~${gmail.daysUntilExpiry} day(s) left.` : " Reconnect now."}
            </p>
            <a href={gmail.authUrl} className="am-btn am-btn-primary am-copy mt-3 inline-flex px-4 py-2">
              Reconnect Gmail
            </a>
          </Card>
        )}
        {gmail?.connected && !gmail.needsReauth ? (
          <div className="mt-6 flex flex-wrap items-center gap-4">
            <span className="am-detail-meta">{gmail.indexedCount} messages indexed</span>
            <Button onClick={syncInbox} disabled={syncing}>
              {syncing ? "Syncing…" : "Sync inbox"}
            </Button>
            <Button onClick={runTriage} disabled={loading} variant="secondary">
              {loading ? "Reviewing…" : "Review inbox"}
            </Button>
          </div>
        ) : !gmail?.needsReauth && gmail?.authUrl ? (
          <a href={gmail.authUrl} className="am-btn am-btn-primary am-copy mt-6 inline-flex px-4 py-2">
            Connect Gmail
          </a>
        ) : !gmail?.needsReauth ? (
          <p className="am-detail-meta mt-4">{gmail?.message ?? "Loading…"}</p>
        ) : null}
      </Card>

      {searchResults.length > 0 && (
        <div className="am-section space-y-6">
          <h2 className="am-title">search results</h2>
          {searchResults.map((r) => (
            <Card key={r.message_id} padding="md">
              <p className="am-title">{r.sender}</p>
              <p className="am-copy mt-1">{r.subject}</p>
              <p className="am-detail-meta mt-2">{r.why_matched}</p>
              <p className="am-detail-meta mt-1">{r.suggested_action}</p>
            </Card>
          ))}
        </div>
      )}

      <div className="space-y-8">
        {items.map((item) => (
          <Card key={item.message_id} padding="lg">
            <div className="flex items-start justify-between gap-4">
              <div>
                <p className="am-title">{item.sender}</p>
                <p className="am-detail-meta mt-1">{item.subject}</p>
              </div>
              <Badge tone={priorityTone[item.priority]}>{item.priority}</Badge>
            </div>
            <p className="am-copy mt-4">{item.why_it_matters}</p>
            <p className="am-detail-meta mt-2">
              {item.classification.replace(/_/g, " ")} · {item.suggested_action}
            </p>
            {item.suggested_reply && (
              <div className="mt-4 rounded border border-border p-3">
                <p className="am-label mb-2">suggested reply</p>
                <p className="am-copy whitespace-pre-wrap">{item.suggested_reply}</p>
              </div>
            )}
            <div className="mt-6 flex flex-wrap gap-2">
              {item.classification === "needs_reply" && (
                <>
                  <Button onClick={() => draftReply(item.message_id)} variant="secondary" size="sm">
                    Draft reply
                  </Button>
                  <Button
                    onClick={() => draftReply(item.message_id, true)}
                    variant="ghost"
                    size="sm"
                  >
                    → William
                  </Button>
                </>
              )}
              <Button onClick={() => confirmArchive(item.message_id)} variant="secondary" size="sm">
                Archive
              </Button>
              {item.handoff_agent && (
                <Button
                  onClick={() => handoff(item.message_id, item.handoff_agent!, item)}
                  variant="ghost"
                  size="sm"
                >
                  → {item.handoff_agent}
                </Button>
              )}
            </div>
            {expandedReply === item.message_id && drafts[item.message_id] && (
              <div className="mt-6 space-y-3">
                {williamHandoffs[item.message_id] && (
                  <p className="am-detail-meta">William handoff queued ({williamHandoffs[item.message_id].slice(0, 8)}…)</p>
                )}
                <textarea
                  value={drafts[item.message_id]}
                  onChange={(e) => setDrafts((d) => ({ ...d, [item.message_id]: e.target.value }))}
                  rows={6}
                  className="am-input am-copy w-full px-3 py-2"
                />
                <Button onClick={() => saveDraft(item.message_id, item.thread_id)} size="sm">
                  Save draft in Gmail
                </Button>
              </div>
            )}
          </Card>
        ))}
        {!items.length && gmail?.connected && !searchResults.length && (
          <p className="am-copy py-8 text-center">Sync and review your inbox, or ask Marc to search.</p>
        )}
      </div>
    </>
  );
}

export default function InboxPage() {
  return (
    <Suspense fallback={<div className="p-10 text-center am-copy">Loading…</div>}>
      <InboxContent />
    </Suspense>
  );
}
