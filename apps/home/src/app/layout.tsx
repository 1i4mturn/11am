import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "11am",
  description: "11am agent suite",
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
