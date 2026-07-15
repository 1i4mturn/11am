import { runInSandbox } from "../sandbox";

export interface AuditResult {
  npm_audit: { stdout: string; stderr: string; exitCode: number };
  osv_scanner?: { stdout: string; stderr: string; exitCode: number };
  summary: string;
}

export async function runDependencyAudit(
  sandboxImage: string,
  workspacePath: string
): Promise<AuditResult> {
  const npm_audit = await runInSandbox(sandboxImage, workspacePath, [
    "sh",
    "-c",
    "if [ -f package.json ]; then npm audit --json 2>/dev/null || npm audit 2>&1; else echo '{\"error\":\"no package.json\"}'; fi",
  ]);

  let osv_scanner: AuditResult["osv_scanner"];
  try {
    osv_scanner = await runInSandbox(sandboxImage, workspacePath, [
      "sh",
      "-c",
      "if command -v osv-scanner >/dev/null 2>&1 && [ -f package-lock.json ]; then osv-scanner --lockfile=package-lock.json 2>&1; else echo 'osv-scanner not available'; fi",
    ]);
  } catch {
    osv_scanner = undefined;
  }

  const vulnMatch = npm_audit.stdout.match(/"vulnerabilities"/);
  const summary = vulnMatch
    ? "Dependency audit completed - review npm_audit output for vulnerabilities."
    : npm_audit.stdout.includes("no package.json")
      ? "No package.json - skipped npm audit."
      : "Dependency audit completed.";

  return { npm_audit, osv_scanner, summary };
}
