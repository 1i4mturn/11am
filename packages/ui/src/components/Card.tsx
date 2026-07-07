import type { ReactNode } from "react";

export interface CardProps {
  children: ReactNode;
  className?: string;
  padding?: "sm" | "md" | "lg";
  /** Apply fine grain pass on card surface (Bolton) */
  grain?: boolean;
}

const paddingMap = {
  sm: "p-6",
  md: "p-6 md:p-8",
  lg: "p-8",
};

export function Card({ children, className = "", padding = "md", grain = false }: CardProps) {
  return (
    <div
      className={`am-card ${grain ? "am-card-grain overflow-hidden" : ""} ${paddingMap[padding]} ${className}`}
    >
      {children}
    </div>
  );
}
