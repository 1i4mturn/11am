import type { Metadata } from "next";
import { AppShell } from "@11am/ui";
import "./globals.css";

export const metadata: Metadata = {
  title: "William — 11am Writing Agent",
  description: "Copy in your voice, not generic AI output.",
};

const NAV = [
  { href: "/", label: "Write" },
  { href: "/setup", label: "Voice setup" },
];

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" className="h-full antialiased">
      <body className="min-h-screen">
        <AppShell agent="william" logoSrc="/logos/william_wm.svg" nav={NAV}>
          {children}
        </AppShell>
      </body>
    </html>
  );
}
