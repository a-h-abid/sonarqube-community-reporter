# Renders the "Trend / Changes since last report" Markdown section.
# Emits nothing when the report data carries no `.trend` object.
def fmt: if . == null then "N/A" else tostring end;

def signed:
  if . == null then "n/a"
  elif . > 0 then "+" + tostring
  else tostring end;

if (.trend // null) == null then empty else
  .trend as $t |
  "## Trend / Changes since last report\n\n" +
  "Baseline: `" + ($t.baseline.file // "?") + "`" +
  (if ($t.baseline.reportDate // "") != "" then " (" + $t.baseline.reportDate + ")" else "" end) +
  "\n\n" +
  "| Metric | Previous | Current | Change |\n" +
  "|--------|----------|---------|--------|\n" +
  "| **Quality Gate** | " + $t.qualityGate.previous + " | " + $t.qualityGate.current + " | " +
    (if $t.qualityGate.regressed then "❌ regressed"
     elif $t.qualityGate.improved then "✅ improved"
     elif $t.qualityGate.changed then "changed"
     else "→ unchanged" end) + " |\n" +
  ([$t.metrics | to_entries[] |
    "| **" + .value.label + "** | " + (.value.previous | fmt) + " | " + (.value.current | fmt) +
    " | " + .value.indicator + " " + (.value.delta | signed) + " |"
   ] | join("\n")) + "\n" +
  "| **New Issues** | — | " + ($t.issues.new | tostring) + " | " +
    (if $t.issues.new > 0 then "↑ +" + ($t.issues.new | tostring) else "→ 0" end) + " |\n" +
  "| **Fixed Issues** | — | " + ($t.issues.fixed | tostring) + " | " +
    (if $t.issues.fixed > 0 then "↓ -" + ($t.issues.fixed | tostring) else "→ 0" end) + " |\n\n" +
  (if $t.regression
   then "> ❌ **Regression detected** against the baseline.\n"
   else "> ✅ No regression against the baseline.\n" end) +
  "\n---"
end
