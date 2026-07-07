import type { Metadata } from "next";
import { AppShell } from "@11am/ui";
import "./globals.css";

export const metadata: Metadata = {
  title: "Harris — 11am Learning Agent",
  description: "Study paths, skill-building, and practice for LiamOS.",
};

const NAV = [{ href: "/", label: "Learn" }];

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" className="h-full antialiased">
      <body className="min-h-screen">
        <AppShell agent="harris" logoSrc="/logos/harris_hr.svg" nav={NAV}>
          {children}
        </AppShell>
      </body>
    </html>
  );
}
