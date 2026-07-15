import type { Metadata } from "next";
import { AppShell } from "@11am/ui";
import "./globals.css";

export const metadata: Metadata = {
  title: "Cole - 11am Video Agent",
  description: "Scripts, storyboards, and motion direction for LiamOS.",
};

const NAV = [{ href: "/", label: "Motion" }];

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" className="h-full antialiased">
      <body className="min-h-screen">
        <AppShell agent="cole" logoSrc="/logos/cole_co.svg" nav={NAV}>
          {children}
        </AppShell>
      </body>
    </html>
  );
}
