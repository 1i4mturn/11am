export interface GeorgeLatestNumbers {
  source_agent: "George";
  as_of: string;
  revenue: string;
  margin_pct: number;
  runway_months: number;
  burn_rate: string;
  flags: string[];
  confidence: "high" | "medium" | "low";
}

export interface UnitEconomicsInput {
  cac?: number;
  ltv?: number;
  arpu?: number;
  gross_margin_pct?: number;
  monthly_churn_pct?: number;
  payback_months?: number;
  customers?: number;
  notes?: string;
}

export type ModelType = "pl" | "runway" | "cashflow" | "breakeven" | "unit_economics" | "general";

export type Cadence = "once" | "daily" | "weekly" | "monthly" | "custom";

export interface TaxFlag {
  category: string;
  description: string;
  severity: "info" | "review";
}
