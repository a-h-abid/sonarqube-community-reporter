["Metric","Value"],
["Project Key", (.metadata.projectKey // "N/A")],
["Project Name", (.metadata.projectName // .metadata.projectKey // "N/A")],
["Branch", (.metadata.branch // "main")],
["Report Date", (.metadata.reportDate // "N/A")],
["Last Analysis Date", (.metadata.lastAnalysisDate // "N/A")],
["Analysis ID", (.metadata.analysisId // "N/A")],
["SonarQube URL", (.metadata.sonarUrl // "N/A")],
["Quality Gate Status", (.qualityGate.status // "UNKNOWN")],
(if (.metadata | has("qualityGateName"))
 then ["Quality Gate Name", ((.metadata.qualityGateName // "") | if . == "" then "N/A" else . end)]
 else empty end),
((.metadata.qualityProfiles // [])[] | ["Quality Profile (" + (.languageName // .language // "?") + ")", (.name // "N/A")]),
["Bugs", (.measures.bugs // "0")],
["Vulnerabilities", (.measures.vulnerabilities // "0")],
["Code Smells", (.measures.code_smells // "0")],
["Coverage (%)", (.measures.coverage // "N/A")],
["Duplicated Lines Density (%)", (.measures.duplicated_lines_density // "N/A")],
["Lines of Code", (.measures.ncloc // "0")],
["Technical Debt (min)", (.measures.sqale_index // "0")],
["Debt Ratio (%)", (.measures.sqale_debt_ratio // "N/A")],
["Reliability Rating", (.measures.reliability_rating // "N/A")],
["Security Rating", (.measures.security_rating // "N/A")],
["Maintainability Rating", (.measures.sqale_rating // "N/A")],
["Security Hotspots Reviewed (%)", (.measures.security_hotspots_reviewed // "N/A")],
["Security Review Rating", (.measures.security_review_rating // "N/A")],
["New Bugs", (.measures.new_bugs // "N/A")],
["New Vulnerabilities", (.measures.new_vulnerabilities // "N/A")],
["New Code Smells", (.measures.new_code_smells // "N/A")],
["New Coverage (%)", (.measures.new_coverage // "N/A")],
["New Duplicated Lines Density (%)", (.measures.new_duplicated_lines_density // "N/A")],
(if (.metadata.filtersApplied // null) != null
 then ["Filters Applied",
       (.metadata.filtersApplied as $f
        | ([ (if ($f.severityThreshold // "") != "" then "severity>=" + $f.severityThreshold else empty end),
             (if (($f.issueTypes // []) | length) > 0 then "types " + ($f.issueTypes | join("/")) else empty end),
             (if ($f.maxIssues // null) != null then "max " + ($f.maxIssues | tostring) else empty end) ]
           | join("; "))
          + " - showing " + (($f.issuesShown // 0) | tostring) + " of " + (($f.issuesBeforeFilter // 0) | tostring)
          + " issues (summary reflects full project)")]
 else empty end),
(if (.trend // null) != null
 then (.trend as $t
       | ["Trend / Changes since last report", ("baseline: " + ($t.baseline.file // "?"))],
         ["Trend Quality Gate", ($t.qualityGate.previous + " -> " + $t.qualityGate.current)],
         ($t.metrics | to_entries[]
          | ["Trend " + .value.label,
             (.value.indicator + " " +
              (if .value.delta == null then "n/a"
               elif .value.delta > 0 then "+" + (.value.delta | tostring)
               else (.value.delta | tostring) end))]),
         ["Trend New Issues", ($t.issues.new | tostring)],
         ["Trend Fixed Issues", ($t.issues.fixed | tostring)],
         ["Trend Regression", (if $t.regression then "yes" else "no" end)])
 else empty end),
["Total Issues", (.issuesSummary.total // 0 | tostring)],
["Hotspots Total", (.hotspotsSummary.total // 0 | tostring)],
["Hotspots To Review", (.hotspotsSummary.toReview // 0 | tostring)],
["Hotspots Reviewed", (.hotspotsSummary.reviewed // 0 | tostring)]
| @csv
