# ==============================================================================
# sarif.jq — Build a SARIF 2.1.0 document from the unified report data.
#
# Emits one run containing:
#   - tool.driver.rules[] : de-duplicated by SonarQube rule key
#   - results[]           : every issue + every TO_REVIEW security hotspot
#
# Arguments (via --arg):
#   toolName     analyzer name shown in SARIF-aware tools
#   toolVersion  reporter version string (omitted from output when empty)
#   toolUri      informationUri for the tool driver (omitted when empty)
#
# Findings whose component is empty/null are dropped (GitHub cannot anchor a
# fileless alert); the wrapper logs how many were skipped.
# ==============================================================================

# Truncate a string to $n codepoints (SARIF/GitHub cap descriptions at 1024).
def trunc($n): if (. != null and (. | length) > $n) then .[:$n] else . end;

# SonarQube issue severity -> SARIF level.
def issue_level:
  if   . == "BLOCKER"  then "error"
  elif . == "CRITICAL" then "error"
  elif . == "MAJOR"    then "warning"
  else "note" end;

# SonarQube issue severity -> GitHub security-severity (string, 0-10).
def issue_secsev:
  if   . == "BLOCKER"  then "9.0"
  elif . == "CRITICAL" then "7.0"
  elif . == "MAJOR"    then "5.0"
  elif . == "MINOR"    then "3.0"
  else "1.0" end;

# Hotspot vulnerabilityProbability -> SARIF level.
def hotspot_level:
  if   . == "HIGH"   then "error"
  elif . == "MEDIUM" then "warning"
  else "note" end;

# Hotspot vulnerabilityProbability -> security-severity (string).
def hotspot_secsev:
  if   . == "HIGH"   then "8.0"
  elif . == "MEDIUM" then "5.0"
  else "2.0" end;

. as $root
| ($root.metadata.projectKey // "")                        as $projectKey
| (($root.metadata.sonarUrl // "") | sub("/+$"; ""))        as $sonarUrl
| ($root.metadata.branch // "")                             as $branch
| ($root.metadata.analysisId // "")                         as $analysisId
| ($root.metadata.sonarCloud // false)                      as $sonarCloud
| ($root.metadata.organization // "")                       as $organization

# --- Normalize issues into a common finding shape -------------------------
| [ $root.issues[]?
    | {
        key:              (.key // ""),
        rule:             (.rule // ""),
        message:          (.message // .rule // "SonarQube finding"),
        component:        (.component // ""),
        startLine:        (.startLine // .line),
        endLine:          (.endLine // .startLine // .line),
        level:            (.severity | issue_level),
        isSecurity:       (.type == "VULNERABILITY"),
        securitySeverity: (if .type == "VULNERABILITY" then (.severity | issue_secsev) else null end),
        tags:             (["sonarqube", (.type // "")] | map(select(. != ""))),
        ruleDescription:  .ruleDescription
      }
  ] as $issueFindings

# --- Normalize TO_REVIEW hotspots (reviewed ones are excluded) ------------
| [ $root.hotspots[]?
    | select(.status == "TO_REVIEW")
    | {
        key:              (.key // ""),
        rule:             (.rule // ""),
        message:          (.message // .rule // "Security hotspot"),
        component:        (.component // ""),
        startLine:        (.startLine // .line),
        endLine:          (.endLine // .startLine // .line),
        level:            (.vulnerabilityProbability | hotspot_level),
        isSecurity:       true,
        securitySeverity: (.vulnerabilityProbability | hotspot_secsev),
        tags:             (["sonarqube", "security"]
                            + (if (.securityCategory // "") != ""
                               then ["external/sonarqube/\(.securityCategory)"] else [] end)),
        ruleDescription:  .ruleDescription
      }
  ] as $hotspotFindings

# Drop findings with no file to anchor to.
| [ ($issueFindings + $hotspotFindings)[] | select(.component != "") ] as $findings

# --- Build the de-duplicated rules[] array and a key->index map -----------
| ($findings | map(.rule) | unique) as $ruleKeys
| ($ruleKeys | to_entries | map({ key: .value, value: .key }) | from_entries) as $ruleIndex

| ( $ruleKeys
    | map(
        . as $rk
        | ($findings | map(select(.rule == $rk)))                                   as $rf
        | ($rf | map(select(.ruleDescription != null)) | (.[0].ruleDescription))    as $desc
        | ($rf | map(select(.securitySeverity != null)) | (.[0].securitySeverity))  as $secsev
        | (($rf | map(select(.isSecurity)) | length) > 0)                           as $isSec
        | ($rf | map(.tags[]?) | unique)                                            as $tags
        | { id: $rk, name: $rk }
          + (if $desc != null and (($desc.whyTextShort // $desc.whyText // "") != "")
             then { shortDescription: { text: (($desc.whyTextShort // $desc.whyText) | trunc(1024)) } } else {} end)
          + (if $desc != null and (($desc.whyText // "") != "")
             then { fullDescription: { text: ($desc.whyText | trunc(1024)) } } else {} end)
          + (if $desc != null and ((($desc.whyText // "") != "") or (($desc.howToFixText // "") != ""))
             then { help: { text: ([($desc.whyText // ""), ($desc.howToFixText // "")]
                                    | map(select(. != "")) | join("\n\n")) } } else {} end)
          + (if $sonarUrl != "" then { helpUri: "\($sonarUrl)/coding_rules?open=\($rk | @uri)" } else {} end)
          + { properties: ({ tags: $tags }
                            + (if ($isSec and $secsev != null) then { "security-severity": $secsev } else {} end)) }
      )
  ) as $rules

# --- Build results[] ------------------------------------------------------
| ( $findings
    | map(
        {
          ruleId:    .rule,
          ruleIndex: $ruleIndex[.rule],
          level:     .level,
          message:   { text: .message },
          locations: [
            { physicalLocation:
                ({ artifactLocation: { uri: (.component | ltrimstr($projectKey + ":")) } }
                 + (if (.startLine != null and .startLine >= 1)
                    then { region: { startLine: .startLine,
                                     endLine: (if (.endLine != null and .endLine >= .startLine)
                                               then .endLine else .startLine end) } }
                    else {} end))
            }
          ]
        }
        + (if .key != "" then { partialFingerprints: { "sonarIssueKey/v1": .key } } else {} end)
      )
  ) as $results

# --- Assemble the SARIF document ------------------------------------------
| {
    "$schema": "https://raw.githubusercontent.com/oasis-tcs/sarif-spec/master/Schemata/sarif-schema-2.1.0.json",
    version: "2.1.0",
    runs: [
      {
        tool: { driver:
          ({ name: $toolName, rules: $rules }
           + (if $toolVersion != "" then { version: $toolVersion, semanticVersion: $toolVersion } else {} end)
           + (if $toolUri != "" then { informationUri: $toolUri } else {} end))
        },
        automationDetails: {
          id: (if $branch != "" then "sonarqube/\($projectKey)/\($branch)/"
               else "sonarqube/\($projectKey)/" end)
        },
        properties:
          ({ sonarUrl: $sonarUrl, sonarCloud: $sonarCloud }
           + (if $analysisId != ""   then { sonarAnalysisId: $analysisId } else {} end)
           + (if $branch != ""       then { branch: $branch } else {} end)
           + (if $organization != "" then { organization: $organization } else {} end)
           + (if ($root.metadata.filtersApplied // null) != null
              then { filtersApplied: $root.metadata.filtersApplied } else {} end)),
        results: $results
      }
    ]
  }
