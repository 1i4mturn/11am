"use client";

import { Button, Card, PageHeader } from "@11am/ui";
import { useEffect, useState } from "react";

export default function RulesPage() {
  const [instruction, setInstruction] = useState("");
  const [proposal, setProposal] = useState<Record<string, unknown> | null>(null);
  const [rules, setRules] = useState<Array<Record<string, unknown>>>([]);
  const [error, setError] = useState("");
  const [notice, setNotice] = useState("");
  const [loading, setLoading] = useState(false);
  const [applying, setApplying] = useState(false);

  function loadRules() {
    fetch("/api/rules")
      .then((r) => r.json())
      .then((d) => {
        if (d.error) setError(d.error);
        else setRules(d.rules ?? []);
      });
  }

  useEffect(() => {
    loadRules();
  }, []);

  async function proposeRule() {
    setLoading(true);
    setError("");
    setNotice("");
    try {
      const res = await fetch("/api/rules", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ instruction }),
      });
      const data = await res.json();
      if (!res.ok) throw new Error(data.error);
      setProposal(data.proposal);
    } catch (e) {
      setError(e instanceof Error ? e.message : "Failed");
    } finally {
      setLoading(false);
    }
  }

  async function confirmApply() {
    if (!proposal?.id) return;
    if (
      !confirm(
        `Apply rule "${String(proposal.rule_name)}"? This will modify matching messages in Gmail after your confirmation.`
      )
    ) {
      return;
    }
    setApplying(true);
    setError("");
    try {
      const res = await fetch("/api/rules", {
        method: "PUT",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ ruleId: proposal.id, confirmed: true }),
      });
      const data = await res.json();
      if (!res.ok) throw new Error(data.error);
      setNotice(`Rule activated - applied to ${data.appliedTo} messages.`);
      setProposal(null);
      setInstruction("");
      loadRules();
    } catch (e) {
      setError(e instanceof Error ? e.message : "Apply failed");
    } finally {
      setApplying(false);
    }
  }

  if (error && !rules.length && !proposal) {
    return <PageHeader title="Inbox rules" description={error} />;
  }

  return (
    <>
      <PageHeader
        title="Inbox rules"
        description="Natural language → rule proposal → you confirm → Marc applies."
      />

      {notice && (
        <Card padding="sm" className="am-section !p-4">
          <p className="am-copy">{notice}</p>
        </Card>
      )}

      <div className="am-section space-y-4">
        <textarea
          value={instruction}
          onChange={(e) => setInstruction(e.target.value)}
          placeholder='e.g. "Always flag messages from JC as high priority"'
          rows={3}
          className="am-input am-copy w-full px-4 py-3"
        />
        <Button onClick={proposeRule} disabled={loading || !instruction.trim()}>
          {loading ? "Proposing…" : "Propose rule"}
        </Button>
      </div>

      {proposal && (
        <Card className="am-section" padding="md">
          <h2 className="am-title">{String(proposal.rule_name)}</h2>
          <p className="am-detail-meta mt-2">
            Would affect ~{String(proposal.preview_matches)} messages
          </p>
          {Array.isArray(proposal.sample_subjects) && proposal.sample_subjects.length > 0 && (
            <ul className="am-detail-meta mt-3 list-inside list-disc">
              {(proposal.sample_subjects as string[]).slice(0, 3).map((s) => (
                <li key={s}>{s}</li>
              ))}
            </ul>
          )}
          <p className="am-copy mt-4">
            Actions: {((proposal.actions as string[]) ?? []).join("; ") || "Review proposal"}
          </p>
          <Button onClick={confirmApply} disabled={applying} className="mt-4">
            {applying ? "Applying…" : "Confirm & apply rule"}
          </Button>
        </Card>
      )}

      <div className="am-section space-y-4">
        <h2 className="am-title">active rules</h2>
        {rules.map((r) => (
          <Card key={String(r.id)} padding="sm" className="!px-4 !py-3">
            <p className="am-copy">
              {String(r.ruleName)}{" "}
              <span className="am-detail-meta">({String(r.status)})</span>
            </p>
          </Card>
        ))}
      </div>
    </>
  );
}
