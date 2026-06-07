# ==============================================================================
# filter-issues.jq — Limit which issues are SHOWN in the report.
#
# Filters the .issues[] array only. Hotspots, issuesSummary, and hotspotsSummary
# are left untouched so summary counts keep reflecting the full project.
#
# Arguments (via --arg; an empty string disables that filter):
#   severityThreshold  keep issues at this severity or higher
#                      (rank BLOCKER>CRITICAL>MAJOR>MINOR>INFO)
#   issueTypes         comma-separated whitelist of BUG/VULNERABILITY/CODE_SMELL
#   maxIssues          keep at most this many issues, applied AFTER the above
#                      (issues arrive sorted by severity desc, so the cap keeps
#                       the highest-severity issues)
#
# When at least one filter is active a provenance block is recorded under
# .metadata.filtersApplied so every report format can surface a note.
# ==============================================================================

# Severity rank: higher number = more severe. Unknown severities rank 0.
def sev_rank:
  if   . == "BLOCKER"  then 5
  elif . == "CRITICAL" then 4
  elif . == "MAJOR"    then 3
  elif . == "MINOR"    then 2
  elif . == "INFO"     then 1
  else 0 end;

($severityThreshold | ascii_upcase)                                  as $threshold
| ($threshold | sev_rank)                                            as $thresholdRank
| ( $issueTypes
    | ascii_upcase
    | split(",")
    | map(gsub("[[:space:]]"; ""))
    | map(select(. != "")) )                                         as $typeList
| ( if ($maxIssues | length) > 0 then ($maxIssues | tonumber) else null end) as $cap
| ( ($threshold != "") or (($typeList | length) > 0) or ($cap != null) )     as $anyFilter
| (.issues // [])                                                    as $original
| ( $original
    | (if $threshold != ""
       then map(select(((.severity // "") | sev_rank) >= $thresholdRank))
       else . end)
    | (if ($typeList | length) > 0
       then map(select(.type as $t | $typeList | index($t)))
       else . end)
    | (if $cap != null then .[0:$cap] else . end) )                  as $filtered
| .issues = $filtered
| if $anyFilter then
    .metadata.filtersApplied = {
      severityThreshold: (if $threshold != "" then $threshold else null end),
      issueTypes:        (if ($typeList | length) > 0 then $typeList else null end),
      maxIssues:         $cap,
      issuesBeforeFilter: ($original | length),
      issuesShown:        ($filtered | length)
    }
  else . end
