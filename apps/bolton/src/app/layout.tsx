import type { Metadata } from "next";
import { AppShell } from "@11am/ui";
import "./globals.css";

export const metadata: Metadata = {
  title: "Bolton — 11am Memory Layer",
  description: "Curated institutional memory for the 11am agent suite.",
};

const PRIMARY_NAV = [{ href: "/", label: "Memory feed" }];

const SECONDARY_NAV = [
  { href: "/search", label: "Search" },
  { href: "/decisions", label: "Decisions" },
  { href: "/entities", label: "Entities" },
  { href: "/projects", label: "Projects" },
  { href: "/conflicts", label: "Conflicts" },
];

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" className="h-full antialiased">
      <body className="min-h-screen">
        <AppShell
          agent="bolton"
          logoSrc="/logos/bolton_bn.svg"
          nav={PRIMARY_NAV}
          secondaryNav={SECONDARY_NAV}
        >
          {children}
        </AppShell>
      </body>
    </html>
  );
}
