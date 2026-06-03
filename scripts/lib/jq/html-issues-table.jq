    def escape_html:
      gsub("&"; "&amp;") | gsub("<"; "&lt;") | gsub(">"; "&gt;");
    def escape_attr:
      gsub("&"; "&amp;") | gsub("<"; "&lt;") | gsub(">"; "&gt;") | gsub("\""; "&quot;");
    def component_path:
      # Show the full path from the project root. The component key is
      # "<projectKey>:<path>"; the path is the final colon-separated segment
      # (project/module keys may themselves contain colons, but paths do not).
      (. // "") as $component |
      ($component | split(":") | last // "");
    def line_display(v):
      (v.startLine // v.line) as $s |
      (v.endLine // v.line) as $e |
      if ($s != null) and ($e != null) and (($e | tonumber? // 0) > ($s | tonumber? // 0))
      then ($s | tostring) + "-" + ($e | tostring)
      else ((v.line // v.startLine // "") | tostring) end;
    def why_html(v; m):
      if v.ruleDescription then
        (if m == "full" then (v.ruleDescription.whyHtml // (v.ruleDescription.whyText | (. // "") | escape_html))
                        else (v.ruleDescription.whyTextShort | (. // "") | escape_html)
         end)
      else "" end;
    def how_to_fix_html(v; m):
      if v.ruleDescription then
        (if m == "full" then (v.ruleDescription.howToFixHtml // (v.ruleDescription.howToFixText | (. // "") | escape_html))
                        else (v.ruleDescription.howToFixTextShort | (. // "") | escape_html)
         end)
      else "" end;
    def code_block(v):
      if v.codeSnippet then
        (v.codeSnippet as $s |
         "<div class=\"code-snippet\"><table class=\"code-table\">" +
         ([$s.lines[]? |
           "<tr class=\"" + (if .highlighted then "code-line code-line-hl" else "code-line" end) + "\">" +
           "<td class=\"code-lineno\">" + (.n | tostring) + "</td>" +
           "<td class=\"code-text\"><pre>" + ((.text // "") | escape_html) + "</pre></td></tr>"
         ] | join("")) +
         "</table></div>")
      else "" end;
    if (.issues | length) > 0 then
      "<div class=\"table-shell issues-shell\"><table class=\"issues-table\"><thead><tr><th>#</th><th>Severity</th><th>Type</th><th>Component</th><th>Line</th><th>Effort</th></tr></thead>" +
      ([.issues | to_entries[]? |
        (.value.component // "") as $component |
        (why_html(.value; $mode)) as $why |
        (how_to_fix_html(.value; $mode)) as $fix |
        (code_block(.value)) as $code |
        "<tbody class=\"issue-entry\"><tr class=\"issue-summary-row\"><td class=\"issue-index\">" + ((.key + 1) | tostring) + "</td>" +
        "<td><span class=\"sev sev-" + (.value.severity // "INFO") + "\">" + (.value.severity // "?") + "</span></td>" +
        "<td><span class=\"type-badge\">" + (.value.type // "?") + "</span></td>" +
        "<td class=\"issue-component\" title=\"" + ($component | escape_attr) + "\"><span class=\"issue-component-path\">" + ($component | component_path | escape_html) + "</span></td>" +
        "<td>" + (line_display(.value) | escape_html) + "</td>" +
        "<td>" + ((.value.effort // "N/A") | escape_html) + "</td></tr>" +
        "<tr class=\"issue-detail-row\"><td colspan=\"6\"><div class=\"issue-detail\"><div class=\"issue-detail-line\"><span class=\"issue-detail-label\">Rule</span><code>" + ((.value.rule // "") | escape_html) + "</code></div><div class=\"issue-detail-line issue-message-line\"><span class=\"issue-detail-label\">Message</span><span class=\"issue-detail-text\">" + ((.value.message // "") | escape_html) + "</span></div>" +
        (if $why != "" then "<div class=\"issue-section\"><div class=\"issue-section-title\">Why is this an issue?</div><div class=\"issue-section-body\">" + $why + "</div></div>" else "" end) +
        (if $code != "" then "<div class=\"issue-section\"><div class=\"issue-section-title\">Affected code</div>" + $code + "</div>" else "" end) +
        (if $fix != "" then "<div class=\"issue-section\"><div class=\"issue-section-title\">How to fix it</div><div class=\"issue-section-body\">" + $fix + "</div></div>" else "" end) +
        "</div></td></tr></tbody>"
      ] | join("")) +
      "</table></div>"
    else
      "<p><em>No open issues found.</em></p>"
    end
