"use client";

import { createContext, useContext } from "react";
import type { NavItem } from "./AppShell";

interface SuiteNavContextValue {
  items: NavItem[];
  actions?: React.ReactNode;
}

const SuiteNavContext = createContext<SuiteNavContextValue>({ items: [] });

export function SuiteNavProvider({
  items,
  actions,
  children,
}: SuiteNavContextValue & { children: React.ReactNode }) {
  return (
    <SuiteNavContext.Provider value={{ items, actions }}>{children}</SuiteNavContext.Provider>
  );
}

export function useSuiteNav() {
  return useContext(SuiteNavContext);
}
