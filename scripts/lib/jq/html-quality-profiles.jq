# Renders the "Quality Profiles" section for the HTML report.
#   - present & non-empty .metadata.qualityProfiles → <h2> + table
#   - present but empty                             → <h2> + "none" note
#   - absent (feature disabled)                     → "" (section hidden)
def esc:
  (. // "") | tostring
  | gsub("&"; "&amp;") | gsub("<"; "&lt;") | gsub(">"; "&gt;");

if (.metadata | has("qualityProfiles")) then
  (.metadata.qualityProfiles // []) as $profiles |
  if ($profiles | length) > 0 then
    "<h2>Quality Profiles</h2>\n" +
    "<table class=\"quality-profiles-table\">\n" +
    "<thead><tr><th>Language</th><th>Profile</th></tr></thead>\n" +
    "<tbody>\n" +
    ([$profiles[] |
      "<tr><td>" + ((.languageName // .language) | esc) + "</td><td>" + (.name | esc) + "</td></tr>"
    ] | join("\n")) +
    "\n</tbody>\n</table>"
  else
    "<h2>Quality Profiles</h2>\n<p class=\"quality-profiles-empty\">No quality profiles found.</p>"
  end
else
  ""
end
