    index($0, ph) {
      n = index($0, ph)
      prefix = substr($0, 1, n - 1)
      suffix = substr($0, n + length(ph))
      printf "%s", prefix
      # Re-emit each line with its newline so significant whitespace inside
      # <pre> blocks (e.g. rule-description code examples) is preserved.
      while ((getline line < cf) > 0) printf "%s\n", line
      close(cf)
      printf "%s\n", suffix
      next
    }
    { print }
