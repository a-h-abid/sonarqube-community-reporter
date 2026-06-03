["Key","Severity","Type","Rule","Component","Line","Message","Effort","Creation Date","End Line","Why"],
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
      (.ruleDescription.whyText // .ruleDescription.whyTextShort // "")
    ]
)
| @csv
