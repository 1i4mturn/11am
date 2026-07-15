import type { Metadata } from "next";
import { AppShell } from "@11am/ui";
import "./globals.css";

export const metadata: Metadata = {
  title: "Leo - 11am Chief of Staff",
  description: "Routing, calendar, tasks, and daily planning for LiamOS.",
};

const NAV = [
  { href: "/", label: "Home" },
  { href: "/plan", label: "Daily plan" },
  { href: "/calendar", label: "Calendar" },
  { href: "/tasks", label: "Tasks" },
  { href: "/reports", label: "Reports" },
  { href: "/invoke", label: "Route agent" },
];

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" className="h-full antialiased">
      <body className="min-h-screen">
        <AppShell agent="leo" logoSrc="/logos/leo_le.svg" nav={NAV}>
          {children}
        </AppShell>
      </body>
    </html>
  );
}
