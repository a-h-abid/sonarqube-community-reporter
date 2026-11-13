    def esc:
      (. // "") | tostring | gsub("&"; "&amp;") | gsub("<"; "&lt;") | gsub(">"; "&gt;");
    # Reduce a value to characters that are safe inside a class attribute.
    def css_token:
      (. // "") | tostring | gsub("[^A-Za-z0-9_-]"; "");
    if (.qualityGate.conditions | length) > 0 then
      "<table><tr><th>Metric</th><th>Status</th><th>Value</th><th>Threshold</th></tr>" +
      ([.qualityGate.conditions[]? |
        "<tr><td>" + (.metric | esc) + "</td>" +
        "<td class=\"cond-" + ((.status // "") | tostring | ascii_downcase | css_token) + "\">" + (.status | esc) + "</td>" +
        "<td>" + ((.actualValue // "N/A") | esc) + "</td>" +
        "<td>" + ((.errorThreshold // "N/A") | esc) + "</td></tr>"
      ] | join("")) +
      "</table>"
    else
      "<p><em>No conditions configured.</em></p>"
    end
