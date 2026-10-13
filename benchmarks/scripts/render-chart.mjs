import { mkdir, readFile, writeFile } from "node:fs/promises";
import { basename, dirname } from "node:path";
import { spawnSync } from "node:child_process";

const input = process.argv[2] ?? "results/latest.json";
const outputSvg = process.argv[3] ?? "results/latest.svg";
const outputPng = outputSvg.replace(/\.svg$/i, ".png");

const benchmark = JSON.parse(await readFile(input, "utf8"));
const rows = benchmark.results
  .map((result) => ({
    name: result.name,
    medianMs: result.summary.medianMs
  }))
  .sort((a, b) => a.medianMs - b.medianMs);

const slowest = Math.max(...rows.map((row) => row.medianMs));
const colors = new Map([
  ["utoo-lint", "#ff7a45"],
  ["bun", "#f9e5c3"],
  ["oxlint", "#ec4899"],
  ["biome", "#62cdf3"],
  ["eslint", "#8b5cf6"]
]);

const width = 1200;
const chartX = 72;
const chartY = 76;
const labelWidth = 150;
const barX = chartX + labelWidth;
const barMaxWidth = 760;
const barHeight = 48;
const rowGap = 84;
const chartBottom = chartY + Math.max(0, rows.length - 1) * rowGap + barHeight;
const captionY = chartBottom + 52;
const height = Math.max(520, chartBottom + 120);
const bars = rows
  .map((row, index) => {
    const y = chartY + index * rowGap;
    const color = colors.get(row.name) ?? "#94a3b8";
    const barWidth = slowest > 0 ? Number(((row.medianMs / slowest) * barMaxWidth).toFixed(3)) : 0;

    return `
      <g>
        <text x="${chartX + labelWidth - 28}" y="${y + 34}" class="tool" text-anchor="end">${escapeXml(displayName(row.name))}</text>
        <rect x="${barX}" y="${y}" width="${barWidth}" height="${barHeight}" fill="${color}"/>
        <text x="${barX + barWidth + 22}" y="${y + 34}" class="value">${formatMs(row.medianMs)}</text>
      </g>`;
  })
  .join("\n");

const generated = new Date(benchmark.generatedAt);
const generatedLabel = Number.isNaN(generated.valueOf())
  ? benchmark.generatedAt
  : generated.toLocaleDateString("en-US", {
      year: "numeric",
      month: "short",
      day: "numeric",
      timeZone: "UTC"
    });

const subtitle = [
  `${benchmark.targetFiles} TypeScript files`,
  `${benchmark.rules.length} shared lint rules`,
  "fresh CLI process",
  `${benchmark.platform}/${benchmark.arch}`
].join(" · ");

const svg = `<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${height}" viewBox="0 0 ${width} ${height}">
  <defs>
    <filter id="softText" x="-20%" y="-20%" width="140%" height="140%">
      <feDropShadow dx="0" dy="1" stdDeviation="1" flood-color="#000000" flood-opacity="0.35"/>
    </filter>
  </defs>

  <rect width="${width}" height="${height}" fill="#15120b"/>

  <style>
    text {
      font-family: Inter, ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      letter-spacing: 0;
      filter: url(#softText);
    }
    .tool { fill: #d7d1c6; font-size: 25px; font-weight: 520; }
    .value { fill: #d7d1c6; font-size: 25px; font-weight: 520; }
    .caption { fill: #8d877c; font-size: 15px; font-weight: 520; }
  </style>

  <line x1="${barX}" y1="${chartY - 12}" x2="${barX}" y2="${chartBottom + 8}" stroke="#544f44"/>

  ${bars}

  <text x="${chartX}" y="${captionY}" class="caption">${escapeXml(subtitle)} · median wall-clock time · lower is better</text>
  <text x="${chartX}" y="${captionY + 30}" class="caption">Source: ${escapeXml(basename(input))} · generated ${escapeXml(generatedLabel)} · linear zero-based scale</text>
</svg>
`;

await mkdir(dirname(outputSvg), { recursive: true });
await writeFile(outputSvg, svg);

const raster = spawnSync("rsvg-convert", ["-w", String(width), "-h", String(height), "-f", "png", "-o", outputPng, outputSvg], {
  encoding: "utf8"
});

if (raster.error || raster.status !== 0) {
  const detail = [raster.error?.message, raster.stderr?.trim()].filter(Boolean).join("\n");
  console.error(`Wrote ${outputSvg}`);
  console.error(`Could not write ${outputPng} with rsvg-convert${detail ? `:\n${detail}` : "."}`);
  process.exitCode = 1;
} else {
  console.log(`Wrote ${outputSvg}`);
  console.log(`Wrote ${outputPng}`);
}

function displayName(name) {
  if (name === "utoo-lint") return "utoo-lint";
  if (name === "bun") return "Bun lint";
  return name[0].toUpperCase() + name.slice(1);
}

function formatMs(value) {
  return `${value.toFixed(2)}ms`;
}

function escapeXml(value) {
  return String(value)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");
}
