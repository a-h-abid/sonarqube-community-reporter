["Key","Severity","Type","Rule","Component","Line","Message","Effort","Creation Date","End Line","Why","New Code","New Since Baseline"],
(
  .issues // []
  | .[]
  | [
      (.key // ""),
      (.severity // ""),
      (.type // ""),
      (.rule // ""),
      (.component // ""),
      ((.line // "") | tostring),
      (.message // ""),
      (.effort // ""),
      (.creationDate // ""),
      ((.endLine // .line // "") | tostring),
      (.ruleDescription.whyText // .ruleDescription.whyTextShort // ""),
      (if has("newCode") then (if .newCode then "Yes" else "No" end) else "" end),
      (if has("newSinceBaseline") then (if .newSinceBaseline then "Yes" else "No" end) else "" end)
    ]
)
| @csv
