import type { Metadata } from "next";
import { AppShell } from "@11am/ui";
import "./globals.css";

export const metadata: Metadata = {
  title: "Johnny - 11am Build Agent",
  description: "Code review, sandboxed build jobs, and technical architecture for LiamOS.",
};

const NAV = [{ href: "/", label: "Build" }];

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" className="h-full antialiased">
      <body className="min-h-screen">
        <AppShell agent="johnny" logoSrc="/logos/johnny_jo.svg" nav={NAV}>
          {children}
        </AppShell>
      </body>
    </html>
  );
}
