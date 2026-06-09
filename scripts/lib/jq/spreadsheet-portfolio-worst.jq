# Portfolio "Worst Offenders" sheet — ranked projects.
["Rank","Project Key","Project Name","Quality Gate","Blocker+Critical","Total Issues"],
(
  .portfolio.worstOffenders // []
  | to_entries[]
  | [
      ((.key + 1) | tostring),
      (.value.projectKey // ""),
      (.value.projectName // ""),
      (.value.gateStatus // "UNKNOWN"),
      (.value.blockerCritical // 0 | tostring),
      (.value.totalIssues // 0 | tostring)
    ]
)
| @csv
