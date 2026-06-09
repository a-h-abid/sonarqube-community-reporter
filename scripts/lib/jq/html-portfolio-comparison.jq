# ==============================================================================
# html-portfolio-comparison.jq — Per-project comparison table (HTML) for a
# portfolio. Input: a portfolio report object. Output: an HTML table (jq -r).
# ==============================================================================
def esc: (. // "") | tostring | gsub("&"; "&amp;") | gsub("<"; "&lt;") | gsub(">"; "&gt;");
def n($x): ($x // 0) | (tonumber? // 0);
def gate_class:
  if   . == "OK"    then "qg-pass"
  elif . == "ERROR" then "qg-fail"
  elif . == "WARN"  then "qg-warn"
  else "qg-none" end;

(.portfolio.projects // []) as $projects
| if ($projects | length) > 0 then
    "<div class=\"table-shell\"><table><thead><tr>"
    + "<th>Project</th><th>Quality Gate</th><th>Bugs</th><th>Vulnerabilities</th>"
    + "<th>Code Smells</th><th>Coverage</th><th>Duplications</th><th>LOC</th>"
    + "</tr></thead><tbody>"
    + ([ $projects[] |
        "<tr><td>" + ((.metadata.projectName // .metadata.projectKey) | esc)
        + " <code>" + (.metadata.projectKey | esc) + "</code></td>"
        + "<td><span class=\"qg-pill " + ((.qualityGate.status // "UNKNOWN") | gate_class) + "\">"
        + ((.qualityGate.status // "UNKNOWN") | esc) + "</span></td>"
        + "<td>" + (n(.measures.bugs) | tostring) + "</td>"
        + "<td>" + (n(.measures.vulnerabilities) | tostring) + "</td>"
        + "<td>" + (n(.measures.code_smells) | tostring) + "</td>"
        + "<td>" + ((.measures.coverage // "N/A") | tostring) + "%</td>"
        + "<td>" + ((.measures.duplicated_lines_density // "N/A") | tostring) + "%</td>"
        + "<td>" + (n(.measures.ncloc) | tostring) + "</td></tr>"
      ] | join(""))
    + "</tbody></table></div>"
  else "<p><em>No projects.</em></p>" end
