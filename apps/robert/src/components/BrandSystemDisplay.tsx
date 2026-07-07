"use client";

import { Badge, Button, Card } from "@11am/ui";
import type { BrandSystemDoc } from "@/lib/types";

function TokenTable({ title, tokens }: { title: string; tokens: Record<string, string> }) {
  return (
    <div>
      <p className="am-label mb-2">{title}</p>
      <div className="overflow-x-auto">
        <table className="am-copy w-full text-sm">
          <tbody>
            {Object.entries(tokens).map(([key, value]) => (
              <tr key={key} className="border-b border-[var(--am-border)]">
                <td className="py-2 pr-4 font-mono text-xs text-[var(--am-muted)]">{key}</td>
                <td className="py-2">
                  {key.includes("color") || value.startsWith("#") ? (
                    <span className="inline-flex items-center gap-2">
                      <span
                        className="inline-block h-4 w-4 rounded border border-[var(--am-border)]"
                        style={{ background: value }}
                      />
                      {value}
                    </span>
                  ) : (
                    value
                  )}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}

interface BrandSystemDisplayProps {
  doc: BrandSystemDoc;
  fromMock?: boolean;
  onRouteJohnny?: () => void;
  onRouteCole?: () => void;
  routing?: boolean;
}

export function BrandSystemDisplay({
  doc,
  fromMock,
  onRouteJohnny,
  onRouteCole,
  routing,
}: BrandSystemDisplayProps) {
  return (
    <Card padding="lg" className="space-y-8">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div>
          <p className="am-label">living brand system</p>
          <p className="am-copy text-lg font-medium">v{doc.version}</p>
        </div>
        <div className="flex flex-wrap gap-2">
          {fromMock && <Badge tone="medium">Mock data</Badge>}
          <Badge tone="low">{doc.source_agent}</Badge>
        </div>
      </div>

      <TokenTable title="colour tokens" tokens={doc.color_tokens} />
      <TokenTable title="type scale" tokens={doc.type_scale} />
      <TokenTable title="spacing tokens" tokens={doc.spacing_tokens} />

      <div>
        <p className="am-label mb-2">motion tokens</p>
        <div className="grid gap-4 md:grid-cols-3">
          <TokenTable title="timing" tokens={doc.motion_tokens.timing} />
          <TokenTable title="easing" tokens={doc.motion_tokens.easing} />
          <div>
            <p className="am-label mb-2">logo safe area</p>
            <p className="am-copy text-sm">{doc.motion_tokens.logo_safe_area}</p>
          </div>
        </div>
      </div>

      {doc.logo_variants.length > 0 && (
        <div>
          <p className="am-label mb-2">logo variants</p>
          <ul className="am-copy space-y-2 text-sm">
            {doc.logo_variants.map((v) => (
              <li key={v.id}>
                <strong>{v.id}</strong> — {v.description}
                {v.usage && <span className="text-[var(--am-muted)]"> · {v.usage}</span>}
              </li>
            ))}
          </ul>
        </div>
      )}

      <div>
        <p className="am-label mb-2">do / don&apos;t</p>
        <ul className="space-y-2">
          {doc.do_dont_rules.map((r, i) => (
            <li key={i} className="flex gap-2 text-sm">
              <Badge tone={r.type === "do" ? "high" : "medium"}>{r.type}</Badge>
              <span className="am-copy">{r.rule}</span>
            </li>
          ))}
        </ul>
      </div>

      <div className="flex flex-wrap gap-3 border-t border-[var(--am-border)] pt-6">
        <Button variant="primary" size="sm" onClick={onRouteJohnny} disabled={routing}>
          Route to Johnny (build)
        </Button>
        <Button variant="secondary" size="sm" onClick={onRouteCole} disabled={routing}>
          Route to Cole (motion)
        </Button>
      </div>
    </Card>
  );
}
