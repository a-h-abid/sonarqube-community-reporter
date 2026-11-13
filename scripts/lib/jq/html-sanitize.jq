# ==============================================================================
# html-sanitize.jq — Allowlist HTML sanitizer (jq module).
#
# Use:  jq -L <this dir> 'include "html-sanitize"; ... | sanitize_html'
#
# Rule descriptions come from the SonarQube server (plugins, custom rules) and
# from saved report JSON, so they are untrusted. sanitize_html rebuilds the
# markup from scratch instead of trying to strip the dangerous parts:
#
#   - Only tags on the allowlist are emitted, and always WITHOUT attributes
#     (so no event handlers, styles, ids, or srcs survive). The one exception
#     is <a href>, kept only for absolute http(s) URLs.
#   - Every other tag is dropped; a "<" that does not start a tag is escaped.
#     Every "<" in the output is therefore one this file wrote itself.
#   - Tags are balanced: unclosed elements are closed, stray closers dropped.
#   - Table markup must be well formed. The report renders descriptions inside
#     a table cell, where a browser reacts to a loose <td>, <tr> or </table> by
#     closing the report's own cell, row or table. So a row/cell/section tag is
#     emitted only directly under the parent it belongs to, within a <table>
#     this fragment opened, and between the structural levels of a table
#     (table > section > row) no other tag is emitted at all.
#     Together with balancing, a description cannot break out of the container
#     it is rendered in.
#   - <h1>-<h6> become bold paragraphs for compact display.
#
# The result is idempotent: sanitizing sanitized output changes nothing.
# Regexes avoid "." so behaviour does not depend on dot-matches-newline flags.
# ==============================================================================

def _hs_allowed:
  { "p": 1, "br": 1, "hr": 1, "ul": 1, "ol": 1, "li": 1, "dl": 1, "dt": 1,
    "dd": 1, "pre": 1, "code": 1, "kbd": 1, "samp": 1, "var": 1, "strong": 1,
    "b": 1, "em": 1, "i": 1, "u": 1, "s": 1, "sub": 1, "sup": 1, "small": 1,
    "mark": 1, "blockquote": 1, "q": 1, "cite": 1, "abbr": 1, "span": 1,
    "div": 1, "table": 1, "thead": 1, "tbody": 1, "tfoot": 1, "tr": 1,
    "th": 1, "td": 1, "caption": 1, "a": 1, "del": 1, "ins": 1,
    "h": 1 };

def _hs_void: { "br": 1, "hr": 1 };

# Parts of a table: only valid in their place inside a <table>.
def _hs_table_part:
  { "caption": 1, "thead": 1, "tbody": 1, "tfoot": 1, "tr": 1, "td": 1, "th": 1 };

# Levels of a table that hold structure, not content.
def _hs_table_structure:
  { "table": 1, "thead": 1, "tbody": 1, "tfoot": 1, "tr": 1 };

# Index of the last entry of $list that is one of $names, or null.
def _hs_last_index($list; $names):
  [ $list | to_entries[] | select(.value as $v | $names | any(. == $v)) | .key ] | .[-1];

# For table part <$name>: how many entries of $stack stay open when it is
# opened, or null when it has no valid place. Works within the innermost open
# <table> only, and closes what is open below the part's parent — the end tags
# HTML lets authors omit ("<td>a<td>b" is two cells).
#   td/th            -> directly under the open row (none open: no place)
#   tr               -> under the open thead/tbody/tfoot, else under the table
#   caption/sections -> directly under the table
def _hs_table_keep($name; $stack):
  _hs_last_index($stack; ["table"]) as $table
  | if $table == null then null
    else
      $stack[$table + 1:] as $inside
      | if $name == "td" or $name == "th" then
          _hs_last_index($inside; ["tr"]) as $row
          | if $row == null then null else $table + $row + 2 end
        elif $name == "tr" then
          _hs_last_index($inside; ["thead", "tbody", "tfoot"]) as $section
          | if $section == null then $table + 1 else $table + $section + 2 end
        else $table + 1 end
    end;

# href of an <a ...> tag token, or null unless it is an absolute http(s) URL
# free of characters that could end the attribute.
def _hs_href:
  . as $t
  | [ ($t | match("\\shref\\s*=\\s*\"([^\"]*)\""; "i") | .captures[0].string),
      ($t | match("\\shref\\s*=\\s*'([^']*)'"; "i") | .captures[0].string),
      ($t | match("\\shref\\s*=\\s*([^\\s\"'>]+)"; "i") | .captures[0].string) ]
  | .[0]
  | if . != null and test("^https?://[^\\s\"'<>`]+$"; "i") then . else null end;

def _hs_open($name; $tag):
  if $name == "h" then "<p><strong>"
  elif $name == "a" then
    ($tag | _hs_href) as $href
    | if $href == null then "<a>"
      else "<a href=\"" + $href + "\" rel=\"noopener noreferrer\">" end
  else "<" + $name + ">" end;

def _hs_close($name):
  if $name == "h" then "</strong></p>" else "</" + $name + ">" end;

def sanitize_html:
  if type != "string" then ""
  else
    # Cosmetic pre-pass: drop script/style blocks whole, so their source text
    # does not show up as prose. Safety does not depend on this step.
    gsub("<script\\b[^>]*>[\\s\\S]*?(?:</script[^>]*>|\\z)"; ""; "i")
    | gsub("<style\\b[^>]*>[\\s\\S]*?(?:</style[^>]*>|\\z)"; ""; "i")
    # Tokenize into comments, tag-like runs, text runs, and lone "<".
    | [ match("<!--[\\s\\S]*?-->|<[^>]*>|[^<]+|<"; "g").string ]
    | reduce .[] as $t ({ out: [], stack: [] };
        if ($t | startswith("<") | not) then
          .out += [$t]
        elif ($t | test("^</?[A-Za-z][A-Za-z0-9]*")) then
          ($t | startswith("</")) as $closing
          | ($t | match("^</?([A-Za-z][A-Za-z0-9]*)") | .captures[0].string | ascii_downcase) as $raw
          | (if ($raw | test("^h[1-6]$")) then "h" else $raw end) as $name
          | (.stack[-1] // "") as $current
          | if (_hs_allowed | has($name) | not) then .
            elif $closing then
              # Close the nearest matching open element and everything inside
              # it. A closer with nothing to close is dropped.
              ([ .stack | to_entries[] | select(.value == $name) | .key ] | .[-1]) as $i
              | if $i == null then .
                else
                  .out += (.stack[$i:] | reverse | map(_hs_close(.)))
                  | .stack = .stack[:$i]
                end
            elif (_hs_table_part | has($name)) then
              _hs_table_keep($name; .stack) as $keep
              | if $keep == null then .
                else
                  .out += (.stack[$keep:] | reverse | map(_hs_close(.)))
                  | .stack = .stack[:$keep] + [$name]
                  | .out += [_hs_open($name; $t)]
                end
            elif (_hs_table_structure | has($current)) then
              # Between table > section > row only table parts may appear.
              .
            elif (_hs_void | has($name)) then
              .out += ["<" + $name + ">"]
            else
              .stack += [$name] | .out += [_hs_open($name; $t)]
            end
        elif ($t | test("^<[!?]")) then .
        else
          .out += [$t | gsub("<"; "&lt;")]
        end)
    | (.out + (.stack | reverse | map(_hs_close(.)))) | join("")
  end;
