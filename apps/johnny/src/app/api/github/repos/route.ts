import { NextResponse } from "next/server";
import { listUserRepos } from "@11am/jobs";

export async function GET() {
  const token = process.env.GITHUB_TOKEN;
  if (!token) {
    return NextResponse.json(
      { error: "GITHUB_TOKEN not configured", repos: [] },
      { status: 200 }
    );
  }

  try {
    const repos = await listUserRepos(token);
    return NextResponse.json({
      repos: repos.map((r) => ({
        name: r.name,
        full_name: r.full_name,
        private: r.private,
        html_url: r.html_url,
        default_branch: r.default_branch,
        description: r.description,
      })),
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : "GitHub error";
    return NextResponse.json({ error: message, repos: [] }, { status: 500 });
  }
}
