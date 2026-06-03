["Key","Status","Resolution","Risk","Rule","Component","Line","Message","Category","Author","Creation Date","Update Date","End Line","Risk Why"],
(
  .hotspots // []
  | .[]
  | [
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
