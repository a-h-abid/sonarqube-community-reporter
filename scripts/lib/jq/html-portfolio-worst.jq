# ==============================================================================
# html-portfolio-worst.jq — Worst-offenders ranking table (HTML) for a portfolio.
# Input: a portfolio report object. Output: an HTML table (jq -r).
# ==============================================================================
def esc: (. // "") | tostring | gsub("&"; "&amp;") | gsub("<"; "&lt;") | gsub(">"; "&gt;");
def gate_class:
  if   . == "OK"    then "qg-pass"
  elif . == "ERROR" then "qg-fail"
  elif . == "WARN"  then "qg-warn"
  else "qg-none" end;

(.portfolio.worstOffenders // []) as $w
| if ($w | length) > 0 then
    "<div class=\"table-shell\"><table><thead><tr>"
    + "<th>Rank</th><th>Project</th><th>Quality Gate</th><th>Blocker+Critical</th><th>Total Issues</th>"
    + "</tr></thead><tbody>"
    + ([ $w | to_entries[] |
        "<tr><td>" + ((.key + 1) | tostring) + "</td>"
        + "<td>" + (.value.projectName | esc) + " <code>" + (.value.projectKey | esc) + "</code></td>"
        + "<td><span class=\"qg-pill " + (.value.gateStatus | gate_class) + "\">" + (.value.gateStatus | esc) + "</span></td>"
        + "<td>" + (.value.blockerCritical | tostring) + "</td>"
        + "<td>" + (.value.totalIssues | tostring) + "</td></tr>"
      ] | join(""))
    + "</tbody></table></div>"
  else "<p><em>No projects.</em></p>" end
