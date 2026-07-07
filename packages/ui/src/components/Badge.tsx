import type { ReactNode } from "react";

const tones = {
  default: "am-pill am-pill-review",
  flag: "am-pill am-pill-flag",
  review: "am-pill am-pill-review",
  signed: "am-pill am-pill-signed",
  /** @deprecated use flag */
  high: "am-pill am-pill-flag",
  /** @deprecated use review */
  medium: "am-pill am-pill-review",
  /** @deprecated use signed */
  low: "am-pill am-pill-signed",
  /** @deprecated use review */
  live: "am-pill am-pill-review",
  /** @deprecated use flag */
  pro: "am-pill am-pill-flag",
} as const;

export interface BadgeProps {
  tone?: keyof typeof tones;
  children: ReactNode;
  className?: string;
}

/** Grayscale status pill — tonal ladder only, no colour */
export function Badge({ tone = "default", children, className = "" }: BadgeProps) {
  return <span className={`${tones[tone]} ${className}`}>{children}</span>;
}
