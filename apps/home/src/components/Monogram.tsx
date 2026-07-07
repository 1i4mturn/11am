import { MONOGRAM_PATHS, type MonogramId } from "../data/monogram-paths";

export type MonogramVariant = "flat" | "emboss-light" | "emboss-dark" | "emboss-bottom";

interface MonogramProps {
  id: MonogramId;
  variant?: MonogramVariant;
  className?: string;
  title?: string;
}

/** Source SVGs ship with fill="#000000" on paths — strip so layer fill colours apply. */
function normalizePaths(raw: string): string {
  return raw
    .replace(/<title>[\s\S]*?<\/title>\s*/g, "")
    .replace(/\sfill="#[0-9a-fA-F]{3,8}"/g, "");
}

function MonogramLayer({
  fill,
  className,
  paths,
}: {
  fill: string;
  className?: string;
  paths: string;
}) {
  return (
    <svg viewBox="0 0 512 512" className={className} aria-hidden="true">
      <g fill={fill} dangerouslySetInnerHTML={{ __html: paths }} />
    </svg>
  );
}

export function Monogram({ id, variant = "flat", className = "", title }: MonogramProps) {
  const raw = MONOGRAM_PATHS[id];
  if (!raw) return null;
  const paths = normalizePaths(raw);

  if (variant === "flat") {
    return (
      <span className={`mono-flat ${className}`.trim()} title={title}>
        <svg viewBox="0 0 512 512" className="mono-flat-svg" aria-hidden="true">
          <g fill="#161616" dangerouslySetInnerHTML={{ __html: paths }} />
        </svg>
      </span>
    );
  }

  const isDark = variant === "emboss-dark";
  const softFill = isDark ? "#3a3a3a" : "#f1f1f1";
  const coreFill = isDark ? "#efefef" : "#f4f4f4";
  const softClass =
    variant === "emboss-bottom" ? "mono-soft mono-soft--bottom" : isDark ? "mono-soft mono-soft--dark" : "mono-soft";
  const coreClass =
    variant === "emboss-bottom" ? "mono-core mono-core--bottom" : isDark ? "mono-core mono-core--dark" : "mono-core";

  return (
    <span className={`mono-emboss ${className}`.trim()} title={title}>
      <MonogramLayer fill={softFill} className={softClass} paths={paths} />
      <MonogramLayer fill={coreFill} className={coreClass} paths={paths} />
    </span>
  );
}
