import type { Metadata } from "next";
import { AppShell } from "@11am/ui";
import "./globals.css";

export const metadata: Metadata = {
  title: "George — 11am Finance Agent",
  description: "Financial modelling, unit economics, and integrations for LiamOS.",
};

const NAV = [
  { href: "/", label: "Model" },
  { href: "/unit-economics", label: "Unit economics" },
  { href: "/calculators", label: "Calculators" },
  { href: "/models", label: "Saved models" },
  { href: "/integrations", label: "Integrations" },
];

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" className="h-full antialiased">
      <body className="min-h-screen">
        <AppShell agent="george" logoSrc="/logos/george_ge.svg" nav={NAV}>
          {children}
        </AppShell>
      </body>
    </html>
  );
}
