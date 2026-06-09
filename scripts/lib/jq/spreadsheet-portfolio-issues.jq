# Portfolio "Issues Details" sheet — every project's issues, Project column first.
["Project","Key","Severity","Type","Rule","Component","Line","Message","Effort","Creation Date","End Line","Why"],
(
  .portfolio.projects // []
  | .[]
  | (.metadata.projectKey // "") as $pk
  | (.issues // [])
  | .[]
  | [
      $pk,
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
