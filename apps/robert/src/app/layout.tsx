import type { Metadata } from "next";
import { AppShell } from "@11am/ui";
import "./globals.css";

export const metadata: Metadata = {
  title: "Robert - 11am Design Agent",
  description: "Visual direction, brand system, and design briefs for LiamOS.",
};

const NAV = [{ href: "/", label: "Direction" }];

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" className="h-full antialiased">
      <body className="min-h-screen">
        <AppShell agent="robert" logoSrc="/logos/robert_rt.svg" nav={NAV}>
          {children}
        </AppShell>
      </body>
    </html>
  );
}
