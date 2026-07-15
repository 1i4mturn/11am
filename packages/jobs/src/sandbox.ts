import { execFile } from "child_process";
import { mkdir, mkdtemp, readFile, readdir } from "fs/promises";
import os from "os";
import path from "path";
import { promisify } from "util";
import type { RepoScope } from "./types";

const exec = promisify(execFile);

export interface SandboxResult {
  stdout: string;
  stderr: string;
  exitCode: number;
}

export async function prepareWorkspace(
  repo: RepoScope,
  githubToken?: string
): Promise<{ workspacePath: string; cleanup: () => Promise<void> }> {
  if (repo.type === "local" && repo.path) {
    return { workspacePath: repo.path, cleanup: async () => {} };
  }

  if (repo.type === "github" && repo.owner && repo.repo) {
    const tmp = await mkdtemp(path.join(os.tmpdir(), "11am-job-"));
    const cloneUrl = githubToken
      ? `https://x-access-token:${githubToken}@github.com/${repo.owner}/${repo.repo}.git`
      : `https://github.com/${repo.owner}/${repo.repo}.git`;
    await exec("git", ["clone", "--depth", "1", "--branch", repo.ref ?? "main", cloneUrl, tmp]);
    return {
      workspacePath: tmp,
      cleanup: async () => {
        await exec("rm", ["-rf", tmp]).catch(() => {});
      },
    };
  }

  throw new Error("Invalid repo scope - provide local path or github owner/repo");
}

export async function runInSandbox(
  image: string,
  workspacePath: string,
  command: string[],
  cwd = "/workspace"
): Promise<SandboxResult> {
  const args = [
    "run",
    "--rm",
    "--network",
    "none",
    "--memory",
    "512m",
    "--cpus",
    "1",
    "-v",
    `${workspacePath}:${cwd}:ro`,
    "-w",
    cwd,
    image,
    ...command,
  ];

  try {
    const { stdout, stderr } = await exec("docker", args, {
      maxBuffer: 10 * 1024 * 1024,
      timeout: 120_000,
    });
    return { stdout, stderr, exitCode: 0 };
  } catch (err: unknown) {
    const e = err as { stdout?: string; stderr?: string; code?: number };
    return {
      stdout: e.stdout ?? "",
      stderr: e.stderr ?? String(err),
      exitCode: typeof e.code === "number" ? e.code : 1,
    };
  }
}

export async function readWorkspaceFile(
  workspacePath: string,
  relativePath: string,
  maxBytes = 100_000
): Promise<string> {
  const full = path.join(workspacePath, relativePath);
  const resolved = path.resolve(full);
  if (!resolved.startsWith(path.resolve(workspacePath))) {
    throw new Error("Path escapes workspace");
  }
  const content = await readFile(resolved, "utf-8");
  return content.slice(0, maxBytes);
}

export async function listWorkspaceDir(
  workspacePath: string,
  relativePath = "."
): Promise<string[]> {
  const full = path.join(workspacePath, relativePath);
  const entries = await readdir(full, { withFileTypes: true });
  return entries.slice(0, 200).map((e) => (e.isDirectory() ? `${e.name}/` : e.name));
}

export async function ensureSandboxImage(image: string): Promise<void> {
  try {
    await exec("docker", ["image", "inspect", image]);
  } catch {
    throw new Error(
      `Sandbox image "${image}" not found. Build with: npm run sandbox:build -w @11am/johnny`
    );
  }
}
