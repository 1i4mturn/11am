"use client";

import { Badge } from "./Badge";
import { Button } from "./Button";

export interface TierToggleProps {
  tier: "free" | "pro";
  onToggle: () => void;
  remaining?: number | null;
  freeLimit?: number;
}

export function TierToggle({ tier, onToggle, remaining, freeLimit = 10 }: TierToggleProps) {
  const isPro = tier === "pro";

  return (
    <div className="flex items-center gap-3">
      <Badge tone={isPro ? "pro" : "default"}>
        {isPro ? "Pro" : "Free"}
        {!isPro && remaining !== undefined && remaining !== null && (
          <span className="ml-1 opacity-80">{remaining} left</span>
        )}
      </Badge>
      <Button variant="ghost" size="sm" onClick={onToggle} type="button">
        Switch to {isPro ? "Free" : "Pro"}
      </Button>
    </div>
  );
}
