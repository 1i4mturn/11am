import type { ReactNode } from "react";

const tones = {
  default: "am-pill",
  pro: "am-pill am-pill-pro",
  high: "am-pill am-pill-urgent",
  medium: "am-pill am-pill-build",
  low: "am-pill",
  live: "am-pill am-pill-live",
} as const;

export interface BadgeProps {
  tone?: keyof typeof tones;
  children: ReactNode;
  className?: string;
}

export function Badge({ tone = "default", children, className = "" }: BadgeProps) {
  return (
    <span className={`am-label ${tones[tone]} ${className}`}>
      {children}
    </span>
  );
}
