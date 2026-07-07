import { createClient } from "@supabase/supabase-js";

const BUCKET = process.env.SUPABASE_CALCULATORS_BUCKET ?? "george-calculators";

function getSupabase() {
  const url = process.env.SUPABASE_URL;
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !key) return null;
  return createClient(url, key);
}

export async function uploadCalculatorArtifact(
  filename: string,
  html: string
): Promise<{ path: string; publicUrl: string | null } | null> {
  const supabase = getSupabase();
  if (!supabase) return null;

  const path = `calculators/${Date.now()}-${filename}`;
  const { error } = await supabase.storage.from(BUCKET).upload(path, html, {
    contentType: "text/html",
    upsert: false,
  });
  if (error) throw new Error(error.message);

  const { data } = supabase.storage.from(BUCKET).getPublicUrl(path);
  return { path, publicUrl: data.publicUrl ?? null };
}

export function isSupabaseConfigured(): boolean {
  return !!(process.env.SUPABASE_URL && process.env.SUPABASE_SERVICE_ROLE_KEY);
}
