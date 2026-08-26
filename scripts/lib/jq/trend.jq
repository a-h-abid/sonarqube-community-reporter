# Computes the normalized `.trend` object and injects it into the current
# report data.
#   input : current report data JSON
#   $base : baseline report data (passed with --slurpfile base <file>)
#   $baselineFile : path the baseline was read from
#
# Metric entries carry both raw numbers and a presentation-ready indicator so
# every generator renders the same arrows without re-deriving the direction.
def to_num: if . == null then null else (tostring | (tonumber? // null)) end;

def round3: (. * 1000 | round) / 1000;

def issue_keys: [ (.issues // [])[] | .key? // empty ];

def metric_entry($name; $previous; $current; $lowerIsBetter):
  (if ($previous == null) or ($current == null) then null
   else ($current - $previous | round3) end) as $delta
  | {
      label: $name,
      previous: $previous,
      current: $current,
      delta: $delta,
      direction: (
        if $delta == null then "unknown"
        elif $delta > 0 then "up"
        elif $delta < 0 then "down"
        else "same" end
      ),
      indicator: (
        if $delta == null then "—"
        elif $delta > 0 then "↑"
        elif $delta < 0 then "↓"
        else "→" end
      ),
      improved: (
        if $delta == null or $delta == 0 then false
        elif $lowerIsBetter then $delta < 0
        else $delta > 0 end
      ),
      regressed: (
        if $delta == null or $delta == 0 then false
        elif $lowerIsBetter then $delta > 0
        else $delta < 0 end
      )
    };

. as $cur
| ($base[0] // {}) as $prev
| ($prev | issue_keys) as $prevKeys
| ($cur | issue_keys) as $curKeys
| ($prev.qualityGate.status // "UNKNOWN") as $prevGate
| ($cur.qualityGate.status // "UNKNOWN") as $curGate
| (
    [ ["bugs",              "Bugs",                        true],
      ["vulnerabilities",   "Vulnerabilities",             true],
      ["code_smells",       "Code Smells",                 true],
      ["coverage",          "Coverage (%)",                false],
      ["duplicated_lines_density", "Duplicated Lines (%)", true],
      ["sqale_index",       "Technical Debt (min)",        true]
    ]
    | map(
        . as [$key, $name, $lowerIsBetter]
        | { key: $key,
            entry: metric_entry(
                     $name;
                     ($prev.measures[$key] | to_num);
                     ($cur.measures[$key] | to_num);
                     $lowerIsBetter) }
      )
  ) as $metrics
| {
    baseline: {
      file: $baselineFile,
      projectKey: ($prev.metadata.projectKey // null),
      branch: ($prev.metadata.branch // null),
      reportDate: ($prev.metadata.reportDate // null)
    },
    qualityGate: {
      previous: $prevGate,
      current: $curGate,
      changed: ($prevGate != $curGate),
      regressed: ($prevGate != "ERROR" and $curGate == "ERROR"),
      improved: ($prevGate == "ERROR" and $curGate != "ERROR"),
      indicator: (
        if $prevGate == $curGate then "→"
        elif $curGate == "ERROR" then "↑"
        else "↓" end
      )
    },
    metrics: ($metrics | map({ (.key): .entry }) | add),
    issues: {
      new: ($curKeys - $prevKeys | length),
      fixed: ($prevKeys - $curKeys | length),
      unchanged: ($curKeys - ($curKeys - $prevKeys) | length),
      newKeys: ($curKeys - $prevKeys),
      fixedKeys: ($prevKeys - $curKeys)
    }
  }
| . + { regression: (.qualityGate.regressed or ([.metrics[] | .regressed] | any)) }
| $cur + { trend: . }
