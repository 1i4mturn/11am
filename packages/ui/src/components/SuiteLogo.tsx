import { brand, suite } from "../tokens";

export interface SuiteLogoProps {
  className?: string;
}

/**
 * 11am wordmark - white embossed monogram (same treatment as the home dashboard),
 * linking back to the suite home.
 */
export function SuiteLogo({ className = "" }: SuiteLogoProps) {
  return (
    <a
      href={suite.homeUrl}
      className={`am-suite-logo ${className}`}
      aria-label={`${brand.name} home`}
    >
      <span className="am-suite-wordmark-emboss" aria-hidden="true">
        <span className="am-suite-wordmark-soft" />
        <span className="am-suite-wordmark-core" />
      </span>
      <span className="am-visually-hidden">{brand.name}</span>
    </a>
  );
}
