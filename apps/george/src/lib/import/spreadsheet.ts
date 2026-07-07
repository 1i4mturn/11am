import * as XLSX from "xlsx";

export function parseSpreadsheet(buffer: Buffer): {
  sheets: Array<{ name: string; rows: string[][] }>;
  textSummary: string;
} {
  const workbook = XLSX.read(buffer, { type: "buffer", cellText: true, cellDates: true });
  const sheets = workbook.SheetNames.map((name) => {
    const sheet = workbook.Sheets[name];
    const rows = XLSX.utils.sheet_to_json<string[]>(sheet, {
      header: 1,
      defval: "",
      raw: false,
    }) as string[][];
    return { name, rows: rows.slice(0, 200) };
  });

  const textSummary = sheets
    .map((s) => {
      const preview = s.rows
        .slice(0, 30)
        .map((row) => row.join("\t"))
        .join("\n");
      return `## Sheet: ${s.name}\n${preview}`;
    })
    .join("\n\n");

  return { sheets, textSummary };
}
