"use client";

import { Badge, Card } from "@11am/ui";
import type { BrandSystemDoc } from "@/lib/types";

interface MotionTokensPanelProps {
  doc: BrandSystemDoc;
  fromMock?: boolean;
  motionTokensReady: boolean;
}

export function MotionTokensPanel({
  doc,
  fromMock,
  motionTokensReady,
}: MotionTokensPanelProps) {
  const { motion_tokens } = doc;

  return (
    <Card padding="lg" className="space-y-6">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div>
          <p className="am-label">robert brand-system · motion tokens</p>
          <p className="am-copy text-sm">v{doc.version}</p>
        </div>
        <div className="flex flex-wrap gap-2">
          {motionTokensReady ? (
            <Badge tone="high">motion tokens ✓</Badge>
          ) : (
            <Badge tone="medium">motion tokens missing</Badge>
          )}
          {fromMock && <Badge tone="low">mock</Badge>}
        </div>
      </div>

      <div className="grid gap-6 md:grid-cols-3">
        <TokenBlock title="timing" tokens={motion_tokens.timing} />
        <TokenBlock title="easing" tokens={motion_tokens.easing} />
        <div>
          <p className="am-label mb-2">logo safe area</p>
          <p className="am-copy text-sm">{motion_tokens.logo_safe_area}</p>
        </div>
      </div>
    </Card>
  );
}

function TokenBlock({ title, tokens }: { title: string; tokens: Record<string, string> }) {
  return (
    <div>
      <p className="am-label mb-2">{title}</p>
      <ul className="am-copy space-y-1 text-sm">
        {Object.entries(tokens).map(([k, v]) => (
          <li key={k}>
            <span className="font-mono text-xs text-[var(--am-muted)]">{k}</span> — {v}
          </li>
        ))}
      </ul>
    </div>
  );
}
