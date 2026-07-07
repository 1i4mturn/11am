import type { ReactNode } from "react";

const tones = {
  default: "bg-accent-light text-muted",
  pro: "bg-foreground text-background",
  high: "text-red-800 bg-red-50",
  medium: "text-amber-900 bg-amber-50",
  low: "bg-accent-light text-muted",
} as const;

export interface BadgeProps {
  tone?: keyof typeof tones;
  children: ReactNode;
  className?: string;
}

export function Badge({ tone = "default", children, className = "" }: BadgeProps) {
  return (
    <span
      className={`inline-flex items-center rounded-full px-3 py-1 text-xs font-medium ${tones[tone]} ${className}`}
    >
      {children}
    </span>
  );
}
