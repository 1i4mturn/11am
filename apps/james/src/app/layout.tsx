import type { Metadata } from "next";
import { AppShell } from "@11am/ui";
import "./globals.css";

export const metadata: Metadata = {
  title: "James - 11am Research Agent",
  description: "Citation-backed research for the LiamOS agent suite.",
};

const NAV = [{ href: "/", label: "Research" }];

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" className="h-full antialiased">
      <body className="min-h-screen">
        <AppShell agent="james" logoSrc="/logos/james_jm.svg" nav={NAV}>
          {children}
        </AppShell>
      </body>
    </html>
  );
}
