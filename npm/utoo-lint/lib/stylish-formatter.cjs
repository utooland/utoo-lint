const { stripVTControlCharacters } = require("node:util");

function formatESLintResults(results, options = {}) {
  const color = shouldUseColor(options);
  const paint = (text, open, close) => color ? `\u001b[${open}m${text}\u001b[${close}m` : text;
  const lines = [""];
  let errorCount = 0;
  let warningCount = 0;
  let fixableErrorCount = 0;
  let fixableWarningCount = 0;

  for (const result of results) {
    if (result.messages.length === 0) continue;
    lines.push(paint(result.filePath, 4, 24));
    // Sort a copy: formatting must not reorder the caller's results or JSON output.
    const messages = [...result.messages].sort((left, right) =>
      (left.line ?? 0) - (right.line ?? 0) || (left.column ?? 0) - (right.column ?? 0)
    );
    const rows = messages.map((message) => [
      String(message.line || 0),
      String(message.column || 0),
      message.fatal || message.severity === 2 ? "error" : "warning",
      // Unlike ESLint stylish, retain punctuation in the original rule message.
      message.message,
      message.ruleId || "",
    ]);
    const widths = [0, 0, 0, 0];
    for (const row of rows) {
      for (let index = 0; index < widths.length; index += 1) {
        widths[index] = Math.max(widths[index], stripVTControlCharacters(row[index]).length);
      }
    }
    for (const [line, column, severity, message, ruleId] of rows) {
      const location = " ".repeat(widths[0] - line.length)
        + paint(`${line}:${column}`, 2, 22)
        + " ".repeat(widths[1] - column.length);
      const label = paint(severity, severity === "error" ? 31 : 33, 39)
        + " ".repeat(widths[2] - severity.length);
      const padding = " ".repeat(widths[3] - stripVTControlCharacters(message).length);
      const description = ruleId ? `${message}${padding}  ${paint(ruleId, 2, 22)}` : message;
      lines.push(`  ${location}  ${label}  ${description}`);
    }
    lines.push("");
    errorCount += result.errorCount;
    warningCount += result.warningCount;
    fixableErrorCount += result.fixableErrorCount ?? 0;
    fixableWarningCount += result.fixableWarningCount ?? 0;
  }

  if (errorCount || warningCount) {
    const summary = (text) => paint(paint(text, 1, 22), errorCount ? 31 : 33, 39);
    lines.push(summary(
      `✖ ${pluralize(errorCount + warningCount, "problem")} (${pluralize(errorCount, "error")}, ${pluralize(warningCount, "warning")})`
    ));
    if (fixableErrorCount || fixableWarningCount) {
      lines.push(summary(
        `  ${pluralize(fixableErrorCount, "error")} and ${pluralize(fixableWarningCount, "warning")} potentially fixable with the \`--fix\` option.`
      ));
    }
    lines.push("");
  }

  return lines.join("\n");
}

function pluralize(count, noun) {
  return `${count} ${noun}${count === 1 ? "" : "s"}`;
}

function shouldUseColor(options) {
  if (typeof options.color === "boolean") return options.color;
  const env = options.env ? { ...process.env, ...options.env } : process.env;
  if (env.NO_COLOR !== undefined || env.NODE_DISABLE_COLORS !== undefined) return false;
  if (env.FORCE_COLOR !== undefined) return env.FORCE_COLOR !== "0";
  if (env.CLICOLOR_FORCE && env.CLICOLOR_FORCE !== "0") return true;
  return env.TERM !== "dumb" && Boolean(process.stdout.isTTY);
}

module.exports = { formatESLintResults };
