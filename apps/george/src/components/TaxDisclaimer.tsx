import { TAX_DISCLAIMER } from "@/lib/config";

export function TaxDisclaimer() {
  return (
    <div className="mb-6 rounded border border-[var(--am-border)] bg-[var(--am-accent-light)] px-4 py-3">
      <p className="am-label mb-1 text-xs">Tax awareness</p>
      <p className="am-copy text-sm text-[var(--am-muted)]">{TAX_DISCLAIMER}</p>
    </div>
  );
}
