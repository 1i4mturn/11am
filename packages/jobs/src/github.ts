export interface GitHubRepo {
  id: number;
  name: string;
  full_name: string;
  private: boolean;
  html_url: string;
  default_branch: string;
  description: string | null;
}

export interface GitHubFile {
  path: string;
  content: string;
  sha: string;
}

const GITHUB_API = "https://api.github.com";

export async function listUserRepos(token: string): Promise<GitHubRepo[]> {
  const res = await fetch(`${GITHUB_API}/user/repos?per_page=100&sort=updated`, {
    headers: {
      Authorization: `Bearer ${token}`,
      Accept: "application/vnd.github+json",
      "X-GitHub-Api-Version": "2022-11-28",
    },
  });
  if (!res.ok) {
    const err = await res.text();
    throw new Error(`GitHub API error: ${res.status} ${err}`);
  }
  return (await res.json()) as GitHubRepo[];
}

export async function fetchRepoFile(
  token: string,
  owner: string,
  repo: string,
  filePath: string,
  ref?: string
): Promise<string> {
  const refParam = ref ? `?ref=${ref}` : "";
  const res = await fetch(
    `${GITHUB_API}/repos/${owner}/${repo}/contents/${filePath}${refParam}`,
    {
      headers: {
        Authorization: `Bearer ${token}`,
        Accept: "application/vnd.github.raw",
        "X-GitHub-Api-Version": "2022-11-28",
      },
    }
  );
  if (!res.ok) throw new Error(`Failed to fetch ${filePath}: ${res.status}`);
  return res.text();
}

export async function fetchRepoDiff(
  token: string,
  owner: string,
  repo: string,
  base: string,
  head: string
): Promise<string> {
  const res = await fetch(
    `${GITHUB_API}/repos/${owner}/${repo}/compare/${base}...${head}`,
    {
      headers: {
        Authorization: `Bearer ${token}`,
        Accept: "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
      },
    }
  );
  if (!res.ok) throw new Error(`Compare failed: ${res.status}`);
  const data = (await res.json()) as { files?: Array<{ filename: string; patch?: string }> };
  const files = data.files ?? [];
  return files
    .map((f) => `--- ${f.filename}\n${f.patch ?? "(binary)"}`)
    .join("\n\n")
    .slice(0, 80_000);
}

export async function fetchDefaultBranch(
  token: string,
  owner: string,
  repo: string
): Promise<string> {
  const res = await fetch(`${GITHUB_API}/repos/${owner}/${repo}`, {
    headers: {
      Authorization: `Bearer ${token}`,
      Accept: "application/vnd.github+json",
      "X-GitHub-Api-Version": "2022-11-28",
    },
  });
  if (!res.ok) throw new Error(`Repo lookup failed: ${res.status}`);
  const data = (await res.json()) as { default_branch?: string };
  return data.default_branch ?? "main";
}
