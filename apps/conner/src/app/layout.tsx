import type { Metadata } from "next";
import { AppShell } from "@11am/ui";
import "./globals.css";

export const metadata: Metadata = {
  title: "Conner - 11am Business Agent",
  description: "Commercial direction, offers, and growth strategy for LiamOS.",
};

const NAV = [{ href: "/", label: "Strategy" }];

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" className="h-full antialiased">
      <body className="min-h-screen">
        <AppShell agent="conner" logoSrc="/logos/conner_cr.svg" nav={NAV}>
          {children}
        </AppShell>
      </body>
    </html>
  );
}
