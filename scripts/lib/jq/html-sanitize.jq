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
#   - Tags are balanced: unclosed elements are closed, stray closers dropped,
#     so a description cannot break out of the container it is rendered in.
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
          | if (_hs_allowed | has($name) | not) then .
            elif (_hs_void | has($name)) then
              (if $closing then . else .out += ["<" + $name + ">"] end)
            elif $closing then
              ([ .stack | to_entries[] | select(.value == $name) | .key ] | .[-1]) as $i
              | if $i == null then .
                else
                  .out += (.stack[$i:] | reverse | map(_hs_close(.)))
                  | .stack = .stack[:$i]
                end
            else
              .stack += [$name] | .out += [_hs_open($name; $t)]
            end
        elif ($t | test("^<[!?]")) then .
        else
          .out += [$t | gsub("<"; "&lt;")]
        end)
    | (.out + (.stack | reverse | map(_hs_close(.)))) | join("")
  end;
