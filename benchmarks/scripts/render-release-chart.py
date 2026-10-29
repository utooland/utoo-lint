#!/usr/bin/env python3
"""Render publishable SVG and PNG charts from run-benchmark.mjs JSON.

Example (from the repository root):
  benchmarks/.tools/chart-venv/bin/python benchmarks/scripts/render-release-chart.py \
    --input benchmarks/results/release-12.json \
    --input benchmarks/results/release-49.json \
    --output benchmarks/results/release-comparison

Every tool is retained. Bar lengths use the same linear, zero-based scale in
all panels; the relative figure is each median divided by its panel's fastest.
"""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import json
import math
from pathlib import Path
import re
import statistics
import textwrap
from typing import Any

try:
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    from matplotlib.ticker import FuncFormatter, MaxNLocator
except ImportError as error:
    raise SystemExit(
        "Install chart dependencies first: python -m pip install "
        "-r benchmarks/chart-requirements.txt"
    ) from error


REQUIRED_TOOLS = {"utoo-lint", "bun", "oxlint", "biome", "eslint"}
COLORS = {
    "utoo-lint": "#1685F8",
    "bun": "#EDBD47",
    "oxlint": "#DF68AA",
    "biome": "#38ABB6",
    "eslint": "#8261D3",
}
DISPLAY_NAMES = {
    "utoo-lint": "utoo-lint",
    "bun": "Bun lint",
    "oxlint": "Oxlint",
    "biome": "Biome",
    "eslint": "ESLint",
}


def number(value: Any, label: str, *, positive: bool = False) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise ValueError(f"{label} must be a number")
    if not math.isfinite(value) or value < 0 or (positive and value == 0):
        raise ValueError(f"{label} must be finite and {'positive' if positive else 'nonnegative'}")
    return float(value)


def integer(value: Any, label: str, *, positive: bool = False) -> int:
    result = number(value, label, positive=positive)
    if not result.is_integer():
        raise ValueError(f"{label} must be an integer")
    return int(result)


def load_benchmark(path: Path) -> dict[str, Any]:
    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, dict) or not isinstance(data.get("results"), list):
        raise ValueError(f"{path}: expected a run-benchmark.mjs JSON object")
    rules = data.get("rules")
    if not isinstance(rules, list) or not rules or len(set(rules)) != len(rules):
        raise ValueError(f"{path}: rules must be a nonempty list of distinct rule IDs")
    data["targetFiles"] = integer(data.get("targetFiles"), f"{path}: targetFiles", positive=True)
    names: set[str] = set()
    for result in data["results"]:
        name = result.get("name")
        if not isinstance(name, str) or name in names:
            raise ValueError(f"{path}: each result needs a distinct tool name")
        names.add(name)
        samples = result.get("samplesMs")
        if not isinstance(samples, list) or not samples:
            raise ValueError(f"{path}: {name} has no measured samples")
        samples = [number(value, f"{path}: {name} sample", positive=True) for value in samples]
        runs = integer(result.get("runs"), f"{path}: {name} runs", positive=True)
        integer(result.get("warmups"), f"{path}: {name} warmups")
        if runs != len(samples):
            raise ValueError(f"{path}: {name} runs differs from its measured sample count")
        median = number(result.get("summary", {}).get("medianMs"), f"{path}: {name} median", positive=True)
        if not math.isclose(median, statistics.median(samples), abs_tol=0.001, rel_tol=0):
            raise ValueError(f"{path}: {name} stored median does not match its samples")
    missing = REQUIRED_TOOLS - names
    if missing:
        raise ValueError(f"{path}: release comparison is missing tools: {', '.join(sorted(missing))}")
    if len({(result["runs"], result["warmups"]) for result in data["results"]}) != 1:
        raise ValueError(f"{path}: all tools must have the same warmup and measured run counts")
    validation = data.get("validation", {})
    if validation and set(validation.get("rules", [])) != set(rules):
        raise ValueError(f"{path}: validation rule set differs from the measured rule set")
    for control in validation.get("tools", []):
        if control.get("cleanDiagnostics") != 0 or control.get("targetDiagnostics") != 0:
            raise ValueError(f"{path}: {control.get('name')} has failed clean-corpus controls")
    if data.get("utooMode") == "npm-cli":
        utoo_result = next(result for result in data["results"] if result["name"] == "utoo-lint")
        if not data.get("utooPackageVersion") or not utoo_result.get("version"):
            raise ValueError(f"{path}: npm-cli mode requires package and actual CLI version provenance")
    data["inputPath"] = path
    return data


def validate_panels(benchmarks: list[dict[str, Any]]) -> None:
    """Do not silently put different machines or corpora on the same comparison."""
    for label, values in (
        ("CPU", [(data.get("cpu") or {}).get("model") for data in benchmarks]),
        ("logical core count", [(data.get("cpu") or {}).get("logicalCores") for data in benchmarks]),
        ("platform", [data.get("platform") for data in benchmarks]),
        ("architecture", [data.get("arch") for data in benchmarks]),
        ("Node version", [data.get("node") for data in benchmarks]),
        ("file count", [data["targetFiles"] for data in benchmarks]),
        ("corpus hash", [(data.get("corpus") or {}).get("sha256") for data in benchmarks]),
    ):
        recorded = {value for value in values if value is not None}
        if len(recorded) > 1:
            raise ValueError(f"Input panels have different {label}; render them separately")


def version_text(result: dict[str, Any], data: dict[str, Any]) -> str:
    name = result["name"]
    raw = str(result.get("version") or "").strip()
    if name == "utoo-lint":
        if data.get("utooMode") == "npm-cli":
            return f"{data['utooPackageVersion']} · npm CLI"
        if data.get("utooMode") == "native" or data.get("utooBuildMode"):
            return f"{data.get('utooBuildMode') or 'local native build'}"
    match = re.search(r"\d+\.\d+\.\d+(?:-[A-Za-z0-9.]+)?", raw)
    version = match.group(0) if match else raw or "version not recorded"
    if name == "bun":
        details = " ".join(str(value) for value in (
            result.get("revision", ""), result.get("packageVersion", ""),
            data.get("bunPackageVersion", ""), raw,
        ))
        if "canary" in details.lower() and "canary" not in version.lower():
            version += " · canary"
    return version


def provenance(data: dict[str, Any]) -> str:
    if data.get("utooMode") == "npm-cli":
        return (
            f"Published npm CLI: {data.get('utooPackageName', '@utoo/lint')}@"
            f"{data['utooPackageVersion']} (launcher and config startup included)."
        )
    if data.get("utooMode") == "native" or data.get("utooBuildMode"):
        return f"utoo-lint: local native binary, {data.get('utooBuildMode') or 'build mode not recorded'}; not the npm CLI."
    return "utoo-lint CLI provenance was not recorded in this input."


def footnotes(benchmarks: list[dict[str, Any]]) -> list[str]:
    """Six visible notes; the full input metadata is embedded in both formats."""
    first = benchmarks[0]
    cpu = first.get("cpu") or {}
    dates = []
    for data in benchmarks:
        raw_date = str(data.get("generatedAt", "date not recorded"))
        try:
            date = datetime.fromisoformat(raw_date.replace("Z", "+00:00")).astimezone(timezone.utc).date().isoformat()
        except ValueError:
            date = raw_date
        if date not in dates:
            dates.append(date)
    notes = [
        f"{cpu.get('model') or 'CPU not recorded'} · {first.get('platform', '?')}/{first.get('arch', '?')} "
        f"{first.get('osRelease', '')} · Node {first.get('node', '?')} · {' / '.join(dates)} UTC."
    ]
    corpus = first.get("corpus") or {}
    corpus_text = f"Synthetic TypeScript corpus: {first['targetFiles']:,} files"
    if corpus.get("totalLines") is not None:
        corpus_text += f" · {corpus['totalLines']:,} lines"
    if corpus.get("totalBytes") is not None:
        corpus_text += f" · {corpus['totalBytes']:,} bytes"
    notes.append(corpus_text + ".")
    result = first["results"][0]
    sampling = first.get("sampling") or "sampling order not recorded"
    if "round-robin" in sampling and "fresh CLI" in sampling:
        sampling = "fresh CLI processes · rotated round-robin"
    notes.append(f"{result['warmups']} warmups + {result['runs']} measured runs/tool · {sampling}.")
    if first.get("utooMode") == "npm-cli":
        invocation = f"Published {first.get('utooPackageName', '@utoo/lint')}@{first['utooPackageVersion']} npm CLI"
        invocation += " · config cache warm after warmups" if result["warmups"] else " · no config-cache warmup"
    else:
        invocation = provenance(first).rstrip(".")
    input_mode = first.get("inputMode") or "input mode not recorded"
    if "explicit file list" in input_mode and "directory discovery excluded" in input_mode:
        input_mode = "explicit files; directory discovery excluded"
    notes.append(f"{invocation} · {input_mode}.")
    bun_details = []
    for data in benchmarks:
        for result in data["results"]:
            if result["name"] == "bun":
                package = result.get("packageVersion") or data.get("bunPackageVersion")
                details = f"revision {result.get('revision') or 'not recorded'} · package pin {package or 'not recorded'}"
                if details not in bun_details:
                    bun_details.append(details)
    canary = any("canary" in text.lower() for text in bun_details)
    notes.append(f"Bun{' canary' if canary else ''}: " + "; ".join(bun_details) + ".")
    notes.append("Synthetic shared non-type-aware rules · linear zero-based ms · x = median/fastest · lower is better.")
    return notes


def full_description(benchmarks: list[dict[str, Any]]) -> str:
    return json.dumps({
        "methodology": footnotes(benchmarks),
        "ratio": "Each median divided by its panel's fastest median; identical linear zero-based limits in all panels.",
        "benchmarks": [{**data, "inputPath": data["inputPath"].name} for data in benchmarks],
    }, ensure_ascii=False, indent=2)


def render(benchmarks: list[dict[str, Any]], output: Path, title: str, dpi: int) -> None:
    matplotlib.rcParams.update({
        "font.family": "DejaVu Sans",
        "svg.fonttype": "none",
        "axes.unicode_minus": False,
        "savefig.facecolor": "white",
    })
    panel_count = len(benchmarks)
    width = 12.8
    wrapped_notes = [
        line for note in footnotes(benchmarks)
        for line in textwrap.wrap(note, width=150, break_long_words=False)
    ]
    footer_height = 0.23 * len(wrapped_notes) + 0.48
    height = 1.6 + panel_count * 4.4 + footer_height
    figure = plt.figure(figsize=(width, height), facecolor="white")
    footer_fraction = footer_height / height
    grid = figure.add_gridspec(
        panel_count, 1, left=0.19, right=0.96,
        bottom=(footer_height + 0.8) / height, top=1 - 2.1 / height,
        hspace=0.70,
    )
    figure.text(0.055, 1 - 0.42 / height, title, fontsize=34, weight="bold", color="#141414", va="top")
    figure.text(
        0.055, 1 - 1.08 / height,
        "Median end-to-end CLI time · Shared-rule comparison · Lower is better",
        fontsize=13.5, color="#555555", va="top",
    )
    slowest = max(result["summary"]["medianMs"] for data in benchmarks for result in data["results"])
    # The same absolute scale is used for both sections, with room for labels.
    axis_limit = slowest * 1.42
    for index, data in enumerate(benchmarks):
        axis = figure.add_subplot(grid[index, 0])
        rows = sorted(data["results"], key=lambda result: result["summary"]["medianMs"])
        fastest = min(result["summary"]["medianMs"] for result in rows)
        medians = [result["summary"]["medianMs"] for result in rows]
        positions = list(range(len(rows)))
        axis.barh(
            positions, medians, height=0.52,
            color=[COLORS.get(result["name"], "#8393A8") for result in rows],
            edgecolor="none", zorder=3,
        )
        axis.set_yticks(positions)
        axis.set_yticklabels([
            f"{DISPLAY_NAMES.get(result['name'], result['name'])}\n{version_text(result, data)}"
            for result in rows
        ], fontsize=13, linespacing=1.45, color="#252525")
        axis.set_xlim(0, axis_limit)
        axis.set_ylim(len(rows) - 0.40, -0.70)
        axis.xaxis.set_major_locator(MaxNLocator(nbins=5, min_n_ticks=3))
        axis.xaxis.set_major_formatter(FuncFormatter(lambda value, _position: f"{value:,.0f}"))
        axis.set_xlabel("Median wall-clock time (ms)", fontsize=12, labelpad=10, color="#555555")
        axis.tick_params(axis="y", length=0, pad=12)
        axis.tick_params(axis="x", colors="#777777", labelsize=11, length=0, pad=8)
        axis.grid(axis="x", color="#E8E8E8", linewidth=0.8, zorder=0)
        for spine in ("top", "right", "bottom"):
            axis.spines[spine].set_visible(False)
        axis.spines["left"].set_color("#7B7B7B")
        axis.spines["left"].set_linewidth(0.8)
        axis.text(
            -0.175, 1.12, f"{len(data['rules'])} Shared Rules", transform=axis.transAxes,
            color="#0878E7", fontsize=24, weight="bold", ha="left", va="bottom",
        )
        for position, median in zip(positions, medians):
            axis.text(
                median + slowest * 0.025, position,
                f"{median:,.2f} ms  ({median / fastest:.2f}x)",
                color="#222222", fontsize=12, ha="left", va="center", clip_on=False,
            )
    figure.add_artist(plt.Line2D(
        [0.055, 0.96], [footer_fraction, footer_fraction],
        transform=figure.transFigure, color="#D9D9D9", linewidth=0.8,
    ))
    line_step = 0.23 / height
    y = footer_fraction - 0.18 / height
    for line in wrapped_notes:
        figure.text(0.055, y, line, fontsize=9.6, color="#5E5E5E", va="top")
        y -= line_step
    output = output.with_suffix("") if output.suffix.lower() in {".png", ".svg"} else output
    output.parent.mkdir(parents=True, exist_ok=True)
    description = full_description(benchmarks)
    for suffix in (".svg", ".png"):
        destination = Path(f"{output}{suffix}")
        figure.savefig(destination, dpi=dpi, metadata={"Title": title, "Description": description})
        print(f"Wrote {destination}")
    plt.close(figure)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--input", type=Path, action="append", required=True, help="Raw benchmark JSON; repeat for multiple panels")
    parser.add_argument("--output", type=Path, default=Path("results/release-comparison"), help="Output stem; both .svg and .png are written")
    parser.add_argument("--title", default="utoo-lint performance", help="Large chart headline")
    parser.add_argument("--dpi", type=int, default=160, help="PNG resolution (default: 160 DPI)")
    args = parser.parse_args()
    if args.dpi < 72:
        parser.error("--dpi must be at least 72")
    try:
        benchmarks = sorted((load_benchmark(path) for path in args.input), key=lambda data: len(data["rules"]))
        validate_panels(benchmarks)
        render(benchmarks, args.output, args.title, args.dpi)
    except (OSError, ValueError, KeyError, TypeError) as error:
        parser.error(str(error))


if __name__ == "__main__":
    main()
