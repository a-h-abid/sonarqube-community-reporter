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
    if (.hotspots | length) > 0 then
      "<div class=\"table-shell hotspots-shell\"><table class=\"hotspots-table\"><thead><tr><th>#</th><th>Status</th><th>Risk</th><th>Component</th><th>Line</th></tr></thead>" +
      ([.hotspots | to_entries[]? |
        (.value.component // "") as $component |
        (.value.ruleDescription.riskText // "") as $risk |
        (why_html(.value; $mode)) as $why |
        (how_to_fix_html(.value; $mode)) as $fix |
        (code_block(.value)) as $code |
        "<tbody class=\"hotspot-entry\"><tr class=\"hotspot-summary-row\"><td class=\"hotspot-index\">" + ((.key + 1) | tostring) + "</td>" +
        "<td><span class=\"status-badge status-" + ((.value.status // "unknown") | ascii_downcase | gsub("_"; "-")) + "\">" + (.value.status // "?") + "</span>" +
        (if (.value.status == "REVIEWED" and ((.value.resolution // "") != ""))
         then " <span class=\"resolution-badge resolution-" + (.value.resolution | ascii_downcase) + "\">" + .value.resolution + "</span>"
         else "" end) +
        "</td>" +
        "<td>" + ((.value.vulnerabilityProbability // "N/A") | escape_html) + "</td>" +
        "<td class=\"hotspot-component\" title=\"" + ($component | escape_attr) + "\"><span class=\"hotspot-component-path\">" + ($component | component_path | escape_html) + "</span></td>" +
        "<td>" + (line_display(.value) | escape_html) + "</td></tr>" +
        "<tr class=\"hotspot-detail-row\"><td colspan=\"5\"><div class=\"hotspot-detail\"><div class=\"hotspot-detail-line\"><span class=\"hotspot-detail-label\">Rule</span><code>" + ((.value.rule // "") | escape_html) + "</code></div><div class=\"hotspot-detail-line hotspot-message-line\"><span class=\"hotspot-detail-label\">Message</span><span class=\"hotspot-detail-text\">" + ((.value.message // "") | escape_html) + "</span></div>" +
        (if $risk != "" then "<div class=\"hotspot-section\"><div class=\"hotspot-section-title\">What's the risk?</div><div class=\"hotspot-section-body\"><p>" + ($risk | escape_html) + "</p></div></div>" else "" end) +
        (if $why != "" then "<div class=\"hotspot-section\"><div class=\"hotspot-section-title\">Why is this an issue?</div><div class=\"hotspot-section-body\">" + $why + "</div></div>" else "" end) +
        (if $code != "" then "<div class=\"hotspot-section\"><div class=\"hotspot-section-title\">Affected code</div>" + $code + "</div>" else "" end) +
        (if $fix != "" then "<div class=\"hotspot-section\"><div class=\"hotspot-section-title\">How to fix it</div><div class=\"hotspot-section-body\">" + $fix + "</div></div>" else "" end) +
        "</div></td></tr></tbody>"
      ] | join("")) +
      "</table></div>"
    else
      "<p><em>No security hotspots found.</em></p>"
    end
