# ==============================================================================
# render-template.awk — Fill {{PLACEHOLDER}} tokens in an HTML template.
#
#   awk -v sf=<scalars_file> -v bf=<blocks_file> -f render-template.awk <tpl>
#
#   sf  lines of "KEY<TAB>value". The value is untrusted text: it is
#       HTML-escaped here (safe in text and in quoted attributes).
#   bf  lines of "KEY<TAB>path". The file at <path> holds ready-made HTML that
#       is inserted as-is, each line re-emitted with its newline so whitespace
#       inside <pre> blocks is preserved.
#
# Substitution is literal (index/substr — no regex, no "&" or delimiter
# specials) and single-pass: inserted text is never re-scanned, so a value
# containing "{{OTHER}}" stays as written. Unknown placeholders are left alone.
# Kept portable for mawk.
# ==============================================================================
function html_escape(s) {
  gsub(/&/, "\\&amp;", s)
  gsub(/</, "\\&lt;", s)
  gsub(/>/, "\\&gt;", s)
  gsub(/"/, "\\&quot;", s)
  gsub(/'/, "\\&#39;", s)
  return s
}

function load_map(file, escape,    line, tab, key) {
  if (file == "") return
  while ((getline line < file) > 0) {
    tab = index(line, "\t")
    if (tab == 0) continue
    key = "{{" substr(line, 1, tab - 1) "}}"
    if (escape) scalar[key] = html_escape(substr(line, tab + 1))
    else block[key] = substr(line, tab + 1)
  }
  close(file)
}

BEGIN {
  load_map(sf, 1)
  load_map(bf, 0)
}

{
  rest = $0
  while ((start = index(rest, "{{")) > 0) {
    close_at = index(substr(rest, start + 2), "}}")
    if (close_at == 0) break
    token = substr(rest, start, close_at + 3)
    printf "%s", substr(rest, 1, start - 1)
    if (token in scalar) {
      printf "%s", scalar[token]
      rest = substr(rest, start + close_at + 3)
    } else if (token in block) {
      while ((getline line < block[token]) > 0) printf "%s\n", line
      close(block[token])
      rest = substr(rest, start + close_at + 3)
    } else {
      printf "{{"
      rest = substr(rest, start + 2)
    }
  }
  printf "%s\n", rest
}
