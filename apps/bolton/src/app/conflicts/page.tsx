"use client";

import { Button, Card, PageHeader } from "@11am/ui";
import { useEffect, useState } from "react";

export default function ConflictsPage() {
  const [conflicts, setConflicts] = useState<Array<Record<string, unknown>>>([]);
  const [scanning, setScanning] = useState(false);

  useEffect(() => {
    fetch("/api/conflicts").then((r) => r.json()).then((d) => setConflicts(d.conflicts ?? []));
  }, []);

  async function runScan() {
    setScanning(true);
    const res = await fetch("/api/conflicts", { method: "POST" });
    const data = await res.json();
    if (data.conflicts) setConflicts(data.conflicts);
    setScanning(false);
  }

  return (
    <>
      <PageHeader
        title="Conflict review"
        description="Outdated or contradictory memory — marked, not silently deleted."
        actions={
          <Button onClick={runScan} disabled={scanning}>
            {scanning ? "Scanning…" : "Scan for conflicts"}
          </Button>
        }
      />
      <div className="space-y-8">
        {conflicts.map((c) => (
          <Card key={String(c.id)} grain padding="md">
            <p className="am-title">{String(c.description ?? c.conflictType)}</p>
            <p className="am-detail-meta mt-2">{String(c.recommendedResolution ?? c.recommended_resolution ?? "")}</p>
          </Card>
        ))}
        {!conflicts.length && <p className="am-copy py-8 text-center">No conflicts detected.</p>}
      </div>
    </>
  );
}
