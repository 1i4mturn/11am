import { brand, suite } from "../tokens";

export interface SuiteLogoProps {
  className?: string;
}

/** 11am wordmark — embossed text, links back to the home dashboard */
export function SuiteLogo({ className = "" }: SuiteLogoProps) {
  return (
    <a href={suite.homeUrl} className={`am-suite-logo am-suite-logo-text ${className}`} aria-label={`${brand.name} home`}>
      {brand.name}
    </a>
  );
}
