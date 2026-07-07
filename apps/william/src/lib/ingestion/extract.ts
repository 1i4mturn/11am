import mammoth from "mammoth";
import * as cheerio from "cheerio";

export async function extractFromDocx(buffer: Buffer): Promise<string> {
  const result = await mammoth.extractRawText({ buffer });
  return result.value.trim();
}

export async function extractFromPdf(buffer: Buffer): Promise<string> {
  const { PDFParse } = await import("pdf-parse");
  const parser = new PDFParse({ data: buffer });
  const result = await parser.getText();
  await parser.destroy();
  return result.text.trim();
}

export async function extractFromUrl(url: string): Promise<string> {
  const response = await fetch(url, {
    headers: {
      "User-Agent": "William/1.0 (11am Voice Agent)",
    },
  });

  if (!response.ok) {
    throw new Error(`Failed to fetch URL: ${response.status}`);
  }

  const html = await response.text();
  const $ = cheerio.load(html);

  $("script, style, nav, footer, header, aside, noscript").remove();

  const article =
    $("article").text() ||
    $("main").text() ||
    $('[role="main"]').text() ||
    $("body").text();

  return article.replace(/\s+/g, " ").trim();
}

export function extractFromText(content: string): string {
  return content.trim();
}

export async function extractContent(
  input: string | Buffer,
  type: "paste" | "txt" | "md" | "docx" | "pdf" | "url"
): Promise<string> {
  switch (type) {
    case "paste":
    case "txt":
    case "md":
      return extractFromText(input as string);
    case "docx":
      return extractFromDocx(input as Buffer);
    case "pdf":
      return extractFromPdf(input as Buffer);
    case "url":
      return extractFromUrl(input as string);
    default:
      throw new Error(`Unsupported type: ${type}`);
  }
}
