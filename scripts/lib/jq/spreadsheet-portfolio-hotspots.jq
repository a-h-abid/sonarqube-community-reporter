# Portfolio "Hotspots Details" sheet — every project's hotspots, Project column first.
["Project","Key","Status","Resolution","Risk","Rule","Component","Line","Message","Category","Author","Creation Date","Update Date","End Line","Risk Why"],
(
  .portfolio.projects // []
  | .[]
  | (.metadata.projectKey // "") as $pk
  | (.hotspots // [])
  | .[]
  | [
      $pk,
      (.key // ""),
      (.status // ""),
      (.resolution // ""),
      (.vulnerabilityProbability // ""),
      (.rule // ""),
      (.component // ""),
      ((.line // "") | tostring),
      (.message // ""),
      (.securityCategory // ""),
      (.author // ""),
      (.creationDate // ""),
      (.updateDate // ""),
      ((.endLine // .line // "") | tostring),
      (.ruleDescription.riskText // .ruleDescription.whyText // .ruleDescription.whyTextShort // "")
    ]
)
| @csv
