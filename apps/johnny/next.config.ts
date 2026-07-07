import type { NextConfig } from "next";
import path from "path";

const nextConfig: NextConfig = {
  transpilePackages: ["@11am/ui", "@11am/jobs"],
  turbopack: { root: path.join(__dirname, "../..") },
  serverExternalPackages: ["@anthropic-ai/sdk"],
};

export default nextConfig;
