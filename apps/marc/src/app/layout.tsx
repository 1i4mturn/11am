import type { Metadata } from "next";
import { AppShell } from "@11am/ui";
import "./globals.css";

export const metadata: Metadata = {
  title: "Marc - 11am Inbox Agent",
  description: "Relationship-aware inbox intelligence.",
};

const NAV = [
  { href: "/", label: "Inbox" },
  { href: "/search", label: "Search" },
  { href: "/briefing", label: "Briefing" },
  { href: "/senders", label: "Senders" },
  { href: "/cleanup", label: "Cleanup" },
  { href: "/rules", label: "Rules" },
];

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" className="h-full antialiased">
      <body className="min-h-screen">
        <AppShell agent="marc" nav={NAV}>
          {children}
        </AppShell>
      </body>
    </html>
  );
}
