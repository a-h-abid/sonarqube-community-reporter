# Portfolio "Project Comparison" sheet — one row per project.
["Project Key","Project Name","Quality Gate","Bugs","Vulnerabilities","Code Smells","Coverage (%)","Duplications (%)","Lines of Code","Total Issues","Hotspots"],
(
  .portfolio.projects // []
  | .[]
  | [
      (.metadata.projectKey // ""),
      (.metadata.projectName // .metadata.projectKey // ""),
      (.qualityGate.status // "UNKNOWN"),
      (.measures.bugs // "0"),
      (.measures.vulnerabilities // "0"),
      (.measures.code_smells // "0"),
      (.measures.coverage // "N/A"),
      (.measures.duplicated_lines_density // "N/A"),
      (.measures.ncloc // "0"),
      (.issuesSummary.total // 0 | tostring),
      (.hotspotsSummary.total // 0 | tostring)
    ]
)
| @csv
