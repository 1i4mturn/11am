import type { ReactNode } from "react";

const variants = {
  primary: "am-btn-primary",
  secondary: "am-btn-secondary",
  ghost: "am-btn-ghost",
} as const;

const sizes = {
  sm: "px-3 py-1.5 am-label",
  md: "px-4 py-2 am-copy",
  lg: "px-6 py-3 am-copy",
} as const;

export interface ButtonProps extends React.ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: keyof typeof variants;
  size?: keyof typeof sizes;
  children: ReactNode;
}

export function Button({
  variant = "primary",
  size = "md",
  className = "",
  children,
  ...props
}: ButtonProps) {
  const isGhost = variant === "ghost";
  return (
    <button
      className={`am-btn ${variants[variant]} ${sizes[size]} ${className}`}
      {...props}
    >
      {children}
    </button>
  );
}
