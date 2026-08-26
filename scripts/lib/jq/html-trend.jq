# Renders the "Trend / Changes since last report" section for the HTML report.
# Emits "" when the report data carries no `.trend` object (section hidden).
def esc:
  (. // "") | tostring
  | gsub("&"; "&amp;") | gsub("<"; "&lt;") | gsub(">"; "&gt;");

def fmt: if . == null then "N/A" else tostring end;

def signed:
  if . == null then "n/a"
  elif . > 0 then "+" + tostring
  else tostring end;

def delta_class($e):
  if $e.regressed then "trend-worse"
  elif $e.improved then "trend-better"
  else "trend-same" end;

if (.trend // null) == null then "" else
  .trend as $t |
  "<h2>Trend / Changes since last report</h2>\n" +
  "<p class=\"trend-baseline\">Baseline: <code>" + ($t.baseline.file | esc) + "</code>" +
  (if ($t.baseline.reportDate // "") != "" then " (" + ($t.baseline.reportDate | esc) + ")" else "" end) +
  "</p>\n" +
  "<table class=\"trend-table\">\n" +
  "<thead><tr><th>Metric</th><th>Previous</th><th>Current</th><th>Change</th></tr></thead>\n" +
  "<tbody>\n" +
  "<tr><td>Quality Gate</td><td>" + ($t.qualityGate.previous | esc) + "</td><td>" +
    ($t.qualityGate.current | esc) + "</td><td class=\"" +
    (if $t.qualityGate.regressed then "trend-worse" elif $t.qualityGate.improved then "trend-better" else "trend-same" end) +
    "\">" +
    (if $t.qualityGate.regressed then "regressed"
     elif $t.qualityGate.improved then "improved"
     elif $t.qualityGate.changed then "changed"
     else "→ unchanged" end) + "</td></tr>\n" +
  ([$t.metrics | to_entries[] | .value as $e |
    "<tr><td>" + ($e.label | esc) + "</td><td>" + ($e.previous | fmt | esc) + "</td><td>" +
    ($e.current | fmt | esc) + "</td><td class=\"" + delta_class($e) + "\">" +
    $e.indicator + " " + ($e.delta | signed) + "</td></tr>"
   ] | join("\n")) + "\n" +
  "<tr><td>New Issues</td><td>—</td><td>" + ($t.issues.new | tostring) + "</td><td class=\"" +
    (if $t.issues.new > 0 then "trend-worse" else "trend-same" end) + "\">" +
    (if $t.issues.new > 0 then "↑ +" + ($t.issues.new | tostring) else "→ 0" end) + "</td></tr>\n" +
  "<tr><td>Fixed Issues</td><td>—</td><td>" + ($t.issues.fixed | tostring) + "</td><td class=\"" +
    (if $t.issues.fixed > 0 then "trend-better" else "trend-same" end) + "\">" +
    (if $t.issues.fixed > 0 then "↓ -" + ($t.issues.fixed | tostring) else "→ 0" end) + "</td></tr>\n" +
  "</tbody>\n</table>\n" +
  (if $t.regression
   then "<p class=\"trend-regression\">❌ Regression detected against the baseline.</p>"
   else "<p class=\"trend-ok\">✅ No regression against the baseline.</p>" end)
end
