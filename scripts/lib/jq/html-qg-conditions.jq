    if (.qualityGate.conditions | length) > 0 then
      "<table><tr><th>Metric</th><th>Status</th><th>Value</th><th>Threshold</th></tr>" +
      ([.qualityGate.conditions[]? |
        "<tr><td>" + .metric + "</td>" +
        "<td class=\"cond-" + (.status | ascii_downcase) + "\">" + .status + "</td>" +
        "<td>" + (.actualValue // "N/A") + "</td>" +
        "<td>" + (.errorThreshold // "N/A") + "</td></tr>"
      ] | join("")) +
      "</table>"
    else
      "<p><em>No conditions configured.</em></p>"
    end
