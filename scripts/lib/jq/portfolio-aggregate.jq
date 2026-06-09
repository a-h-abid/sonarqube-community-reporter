# ==============================================================================
# portfolio-aggregate.jq — Roll up many per-project report objects into one
#                          portfolio report.
#
# Input  : a JSON array (via `jq -s`) of per-project unified report objects,
#          each shaped like the single-project report data (metadata, measures,
#          issuesSummary, hotspotsSummary, issues, hotspots, qualityGate).
# Output : a portfolio report object with:
#            .metadata.reportType == "portfolio"
#            .portfolio.totals          org-wide sums + gate pass/fail counts
#            .portfolio.aggregates      ncloc-weighted coverage / duplication
#            .portfolio.worstOffenders  ranked: failed gate → blocker+critical → total
#            .portfolio.projects[]      the full per-project objects (drill-down)
#
# Arguments (via --arg):
#   reportDate, sonarUrl, sonarCloud ("true"/"false"), organization, branch
# ==============================================================================

# Coerce a possibly-string / possibly-null value to a number (default 0).
def num($x): ($x // 0) | (tonumber? // 0);

# Round to one decimal place.
def r1: (. * 10 | round) / 10;

. as $projects
| ($projects | length) as $count
| {
    metadata: {
      reportType: "portfolio",
      reportDate: $reportDate,
      sonarUrl: $sonarUrl,
      sonarCloud: ($sonarCloud == "true"),
      organization: $organization,
      branch: $branch,
      projectCount: $count,
      projectKeys: [ $projects[] | .metadata.projectKey ]
    },
    portfolio: {
      totals: {
        bugs:            ([ $projects[] | num(.measures.bugs) ]            | add // 0),
        vulnerabilities: ([ $projects[] | num(.measures.vulnerabilities) ] | add // 0),
        code_smells:     ([ $projects[] | num(.measures.code_smells) ]     | add // 0),
        ncloc:           ([ $projects[] | num(.measures.ncloc) ]           | add // 0),
        sqale_index:     ([ $projects[] | num(.measures.sqale_index) ]     | add // 0),
        issues: {
          total: ([ $projects[] | num(.issuesSummary.total) ] | add // 0),
          byType: {
            BUG:           ([ $projects[] | num(.issuesSummary.byType.BUG) ]           | add // 0),
            VULNERABILITY: ([ $projects[] | num(.issuesSummary.byType.VULNERABILITY) ] | add // 0),
            CODE_SMELL:    ([ $projects[] | num(.issuesSummary.byType.CODE_SMELL) ]    | add // 0)
          },
          bySeverity: {
            BLOCKER:  ([ $projects[] | num(.issuesSummary.bySeverity.BLOCKER) ]  | add // 0),
            CRITICAL: ([ $projects[] | num(.issuesSummary.bySeverity.CRITICAL) ] | add // 0),
            MAJOR:    ([ $projects[] | num(.issuesSummary.bySeverity.MAJOR) ]    | add // 0),
            MINOR:    ([ $projects[] | num(.issuesSummary.bySeverity.MINOR) ]    | add // 0),
            INFO:     ([ $projects[] | num(.issuesSummary.bySeverity.INFO) ]     | add // 0)
          }
        },
        hotspots: {
          total:    ([ $projects[] | num(.hotspotsSummary.total) ]    | add // 0),
          toReview: ([ $projects[] | num(.hotspotsSummary.toReview) ] | add // 0),
          reviewed: ([ $projects[] | num(.hotspotsSummary.reviewed) ] | add // 0)
        },
        gatesPassed: ([ $projects[] | select(.qualityGate.status == "OK") ]    | length),
        gatesFailed: ([ $projects[] | select(.qualityGate.status == "ERROR") ] | length),
        gatesOther:  ([ $projects[] | select((.qualityGate.status // "") != "OK" and (.qualityGate.status // "") != "ERROR") ] | length)
      },
      aggregates: {
        coverage: (
          ([ $projects[] | select(.measures.coverage != null) | num(.measures.ncloc) ] | add // 0) as $w
          | if $w > 0
            then (([ $projects[] | select(.measures.coverage != null) | (num(.measures.coverage) * num(.measures.ncloc)) ] | add // 0) / $w | r1)
            else null end
        ),
        duplicated_lines_density: (
          ([ $projects[] | select(.measures.duplicated_lines_density != null) | num(.measures.ncloc) ] | add // 0) as $w
          | if $w > 0
            then (([ $projects[] | select(.measures.duplicated_lines_density != null) | (num(.measures.duplicated_lines_density) * num(.measures.ncloc)) ] | add // 0) / $w | r1)
            else null end
        )
      },
      worstOffenders: (
        [ $projects[]
          | {
              projectKey:      .metadata.projectKey,
              projectName:     (.metadata.projectName // .metadata.projectKey),
              gateStatus:      (.qualityGate.status // "UNKNOWN"),
              blockerCritical: (num(.issuesSummary.bySeverity.BLOCKER) + num(.issuesSummary.bySeverity.CRITICAL)),
              totalIssues:     num(.issuesSummary.total),
              gateRank:        (if (.qualityGate.status // "") == "ERROR" then 0 else 1 end)
            }
        ]
        | sort_by([.gateRank, (- .blockerCritical), (- .totalIssues)])
        | map(del(.gateRank))
      ),
      projects: $projects
    }
  }
