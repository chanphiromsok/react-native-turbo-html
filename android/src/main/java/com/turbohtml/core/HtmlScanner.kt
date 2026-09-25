package com.turbohtml.core

import java.util.Locale

/** Receives the scanner's events; nesting/auto-closing is the sink's job. */
internal interface HtmlSink {
  fun openTag(tag: String, href: String?, selfClosing: Boolean)

  fun closeTag(tag: String)

  fun text(text: String)
}

/**
 * Single-pass, tolerant HTML scanner (Kotlin port of ios/Core/HTMLScanner.swift). A `<` that
 * doesn't start a tag is literal text; comments, `<!…>` and `<?…>` are skipped;
 * `script`/`style` contents are skipped as raw text. Tag names are lowercased.
 */
internal object HtmlScanner {
  private val voidElements =
      setOf("br", "meta", "link", "img", "hr", "input", "area", "base", "col", "embed", "source", "track", "wbr")

  fun scan(html: String, sink: HtmlSink) {
    val n = html.length
    var i = 0
    var textStart = 0

    fun flushText(end: Int) {
      if (end > textStart) sink.text(decodeText(html, textStart, end))
    }

    while (i < n) {
      if (html[i] != '<') {
        i++
        continue
      }

      if (html.startsWith("<!--", i)) {
        flushText(i)
        val end = html.indexOf("-->", i + 4)
        i = if (end < 0) n else end + 3
        textStart = i
        continue
      }

      if (i + 1 < n && (html[i + 1] == '!' || html[i + 1] == '?')) {
        flushText(i)
        val gt = html.indexOf('>', i)
        i = if (gt < 0) n else gt + 1
        textStart = i
        continue
      }

      var j = i + 1
      val closing = j < n && html[j] == '/'
      if (closing) j++

      // Not a tag (e.g. "a < b"): keep the "<" as part of the surrounding text.
      if (j >= n || !isAsciiLetter(html[j])) {
        i++
        continue
      }

      flushText(i)

      val nameStart = j
      while (j < n && isNameChar(html[j])) j++
      val tag = html.substring(nameStart, j).lowercase(Locale.ROOT)

      var href: String? = null
      var selfClosing = false

      while (j < n && html[j] != '>') {
        val c = html[j]
        if (isSpace(c)) {
          j++
          continue
        }
        if (c == '/') {
          selfClosing = true
          j++
          continue
        }

        val attrStart = j
        while (j < n && !isSpace(html[j]) && html[j] != '=' && html[j] != '>' && html[j] != '/') j++
        val attrEnd = j
        while (j < n && isSpace(html[j])) j++

        var valueStart = -1
        var valueEnd = -1
        if (j < n && html[j] == '=') {
          j++
          while (j < n && isSpace(html[j])) j++
          if (j < n && (html[j] == '"' || html[j] == '\'')) {
            val quote = html[j]
            j++
            valueStart = j
            while (j < n && html[j] != quote) j++
            valueEnd = j
            if (j < n) j++
          } else {
            valueStart = j
            while (j < n && !isSpace(html[j]) && html[j] != '>') j++
            valueEnd = j
          }
          selfClosing = false
        }

        if (tag == "a" && !closing && valueStart >= 0 && attrEnd - attrStart == 4 &&
            html.regionMatches(attrStart, "href", 0, 4, ignoreCase = true)) {
          href = decodeText(html, valueStart, valueEnd)
        }
      }

      if (j < n) j++ // consume ">"
      i = j
      textStart = i

      if (closing) {
        sink.closeTag(tag)
        continue
      }

      sink.openTag(tag, href, selfClosing || tag in voidElements)

      // Raw-text elements: skip to their closing tag, which is then scanned normally.
      if (tag == "script" || tag == "style") {
        val end = html.indexOf("</$tag", i, ignoreCase = true)
        i = if (end < 0) n else end
        textStart = i
      }
    }

    flushText(n)
  }

  private fun isAsciiLetter(c: Char) = (c in 'a'..'z') || (c in 'A'..'Z')

  private fun isNameChar(c: Char) = isAsciiLetter(c) || (c in '0'..'9') || c == '-' || c == ':' || c == '_'

  private fun isSpace(c: Char) = c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == '\u000C'

  private val namedEntities =
      mapOf(
          "amp" to 0x26, "lt" to 0x3C, "gt" to 0x3E, "quot" to 0x22, "apos" to 0x27, "nbsp" to 0xA0,
          "ndash" to 0x2013, "mdash" to 0x2014, "hellip" to 0x2026, "bull" to 0x2022, "middot" to 0xB7,
          "lsquo" to 0x2018, "rsquo" to 0x2019, "ldquo" to 0x201C, "rdquo" to 0x201D,
          "laquo" to 0xAB, "raquo" to 0xBB, "copy" to 0xA9, "reg" to 0xAE, "trade" to 0x2122,
          "euro" to 0x20AC, "deg" to 0xB0, "times" to 0xD7,
      )

  /** Resolves `&name;`, `&#123;` and `&#x1F;`; the `;` search is capped so bad input stays linear. */
  fun decodeText(s: String, start: Int, end: Int): String {
    val firstAmp = s.indexOf('&', start)
    if (firstAmp < 0 || firstAmp >= end) return s.substring(start, end)

    val out = StringBuilder(end - start)
    out.append(s, start, firstAmp)
    var k = firstAmp
    while (k < end) {
      val c = s[k]
      if (c != '&') {
        out.append(c)
        k++
        continue
      }
      var semi = -1
      var m = k + 1
      while (m < end && m - k <= 12) {
        val d = s[m]
        if (d == ';') {
          semi = m
          break
        }
        if (d == '&' || d == '<' || isSpace(d)) break
        m++
      }
      val codePoint = if (semi > k + 1) entityCodePoint(s, k + 1, semi) else null
      if (codePoint != null) {
        out.appendCodePoint(codePoint)
        k = semi + 1
      } else {
        out.append(c)
        k++
      }
    }
    return out.toString()
  }

  private fun entityCodePoint(s: String, start: Int, end: Int): Int? {
    if (s[start] == '#') {
      var k = start + 1
      var radix = 10
      if (k < end && (s[k] == 'x' || s[k] == 'X')) {
        radix = 16
        k++
      }
      if (k >= end) return null
      var value = 0L
      while (k < end) {
        val digit = Character.digit(s[k], radix)
        if (digit < 0) return null
        value = value * radix + digit
        if (value > 0x10FFFF) return 0xFFFD
        k++
      }
      val cp = value.toInt()
      return if (cp == 0 || cp in 0xD800..0xDFFF) 0xFFFD else cp
    }
    return namedEntities[s.substring(start, end).lowercase(Locale.ROOT)]
  }
}
