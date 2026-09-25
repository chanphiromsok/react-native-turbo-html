package com.turbohtml.core

import android.graphics.Typeface
import android.text.SpannableStringBuilder
import android.text.Spanned
import android.text.TextPaint
import android.text.style.CharacterStyle
import android.text.style.MetricAffectingSpan
import android.text.style.StrikethroughSpan
import android.text.style.UnderlineSpan
import java.util.regex.Pattern

/** Layout-affecting style, already in pixels. Color is not here: it's applied at draw time. */
internal data class RichTextStyle(
    val fontFamily: String,
    val fontSizePx: Float,
    val lineHeightPx: Float,
    val detectPhoneNumbers: Boolean,
    /** 4dp block gap, in pixels. */
    val blockGapPx: Float,
)

internal enum class RichTextFontWeight(val value: Int) {
  REGULAR(400),
  MEDIUM(500),
  SEMIBOLD(600),
  BOLD(700),
}

/** One block: a `<p>`/`<h*>`/`<li>` row, or bare text at block level. */
internal class RichTextParagraph(
    /** Content only; `<br>` and raw newlines are `\n` (hard break inside the block). */
    val text: CharSequence,
    /** List marker ("•" / "1.") drawn in its own column, like a flex row. */
    val prefix: CharSequence?,
    val spacingBeforePx: Float,
)

internal class RichTextDocument(val paragraphs: List<RichTextParagraph>, val plainText: String)

/** Marks a tappable range; also paints it like a phone link (brand color, underline). */
internal class RichTextLinkSpan(val url: String, val isPhone: Boolean) : CharacterStyle() {
  override fun updateDrawState(tp: TextPaint) {
    tp.color = RichTextColors.LINK
    tp.isUnderlineText = true
  }
}

/** Typeface + size for a run (bundled Figtree / KantumruyPro via ReactFontManager). */
internal class RichTextTypefaceSpan(private val typeface: Typeface, private val sizePx: Float) : MetricAffectingSpan() {
  override fun updateMeasureState(paint: TextPaint) = apply(paint)

  override fun updateDrawState(paint: TextPaint) = apply(paint)

  private fun apply(paint: TextPaint) {
    paint.typeface = typeface
    paint.textSize = sizePx
  }
}

internal object RichTextColors {
  /** Default link color (#04ab52) — see the package README for how to override it. */
  const val LINK = 0xFF04AB52.toInt()
  /** Default body text color per theme — see the package README for how to override it. */
  const val BODY_LIGHT = 0xFF7D7D7D.toInt()
  const val BODY_DARK = 0xFF898989.toInt()
}

/**
 * Builds a [RichTextDocument] with the same rules as a typical RenderHtml-style component
 * (Kotlin port of ios/Core/RichTextDocument.swift — keep the two in sync):
 * - top-level blocks separated by 4dp; blocks inside an unknown wrapper (`<div>`) are not;
 * - `p`/`li`/`h1`–`h6` render their subtree inline; headings keep the base size and change
 *   weight only (Khmer `font-bold` → semibold, as in fontMapper);
 * - `ul`/`ol`: only direct `li` children, "•"/"N." marker column, 4dp gaps;
 * - bare block-level text is its own unstyled block without phone detection;
 * - `head`/`script`/`style`/`meta`/`link` dropped with their contents.
 * Additions over RenderHtml: tappable `a[href]` (http/https/mailto/tel) and `s`/`del`.
 */
internal class RichTextDocumentBuilder
private constructor(
    private val style: RichTextStyle,
    private val typeface: (weight: RichTextFontWeight, italic: Boolean) -> Typeface,
) : HtmlSink {

  companion object {
    fun build(
        html: String,
        style: RichTextStyle,
        typeface: (weight: RichTextFontWeight, italic: Boolean) -> Typeface,
    ): RichTextDocument {
      val builder = RichTextDocumentBuilder(style, typeface)
      HtmlScanner.scan(html, builder)
      builder.closeAll()
      return RichTextDocument(builder.paragraphs, builder.plainText.toString())
    }

    private const val LINE_BREAK = '\n'
    private val allowedLinkSchemes = setOf("http", "https", "mailto", "tel")

    fun linkUrl(href: String): String? {
      var candidate = href.trim()
      if (candidate.isEmpty()) return null
      if (candidate.startsWith("www.", ignoreCase = true)) candidate = "https://$candidate"
      // `Uri.parse` is lenient (spaces, non-ASCII) — only the scheme matters here.
      val scheme = android.net.Uri.parse(candidate).scheme?.lowercase() ?: return null
      return if (scheme in allowedLinkSchemes) candidate else null
    }
  }

  private data class InlineStyle(
      val weight: RichTextFontWeight = RichTextFontWeight.REGULAR,
      val italic: Boolean = false,
      val underline: Boolean = false,
      val strikethrough: Boolean = false,
      val link: RichTextLinkSpan? = null,
  )

  private enum class Kind { GENERIC, LIST, PARAGRAPH, INLINE, IGNORED }

  private class Frame(val kind: Kind, val tag: String, val style: InlineStyle = InlineStyle(), val ordered: Boolean = false) {
    var itemCount = 0
  }

  private val frames = ArrayList<Frame>()
  private val paragraphs = ArrayList<RichTextParagraph>()
  private val plainText = StringBuilder()

  private var current: SpannableStringBuilder? = null
  private var currentPrefix: CharSequence? = null
  private var currentSpacing = 0f
  private var pendingGap = 0f

  private val ignoredTags = setOf("head", "script", "style", "meta", "link")
  private val paragraphTags = setOf("p", "li", "h1", "h2", "h3", "h4", "h5", "h6")

  // MARK: HtmlSink

  override fun openTag(tag: String, href: String?, selfClosing: Boolean) {
    if (frames.lastOrNull()?.kind == Kind.IGNORED) {
      if (!selfClosing) frames.add(Frame(Kind.IGNORED, tag))
      return
    }

    if (current != null) closeParagraphIfImplied(tag)

    if (current != null) {
      openInline(tag, href, selfClosing)
      return
    }

    if (frames.isEmpty()) beginTopLevelChild()

    val parent = frames.lastOrNull()
    if (parent?.kind == Kind.LIST) {
      if (tag == "li") {
        parent.itemCount++
        if (parent.itemCount > 1) pendingGap = style.blockGapPx
        beginParagraph(if (parent.ordered) "${parent.itemCount}." else "•")
        frames.add(Frame(Kind.PARAGRAPH, tag))
      } else if (!selfClosing) {
        frames.add(Frame(Kind.IGNORED, tag)) // non-li children of a list are dropped
      }
      return
    }

    when (tag) {
      in ignoredTags -> if (!selfClosing) frames.add(Frame(Kind.IGNORED, tag))
      in paragraphTags -> {
        beginParagraph(null)
        frames.add(Frame(Kind.PARAGRAPH, tag, InlineStyle(weight = headingWeight(tag))))
      }
      "ul", "ol" -> frames.add(Frame(Kind.LIST, tag, ordered = tag == "ol"))
      else -> if (!selfClosing) frames.add(Frame(Kind.GENERIC, tag))
    }
  }

  override fun closeTag(tag: String) {
    val index = frames.indexOfLast { it.tag == tag }
    if (index >= 0) popTo(index)
  }

  override fun text(text: String) {
    val top = frames.lastOrNull() ?: return appendBlockText(text)
    when (top.kind) {
      Kind.IGNORED, Kind.LIST -> Unit
      Kind.PARAGRAPH, Kind.INLINE -> appendRun(text, top.style, style.detectPhoneNumbers && top.style.link == null)
      Kind.GENERIC -> appendBlockText(text)
    }
  }

  private fun closeAll() {
    popTo(0)
    finishParagraph()
  }

  // MARK: Blocks

  private fun beginTopLevelChild() {
    pendingGap = if (paragraphs.isEmpty()) 0f else style.blockGapPx
  }

  private fun beginParagraph(marker: String?) {
    finishParagraph()
    current = SpannableStringBuilder()
    currentSpacing = pendingGap
    currentPrefix = marker?.let { SpannableStringBuilder(it).also { s -> applyStyle(s, 0, s.length, InlineStyle()) } }
  }

  private fun finishParagraph() {
    val text = current ?: return
    current = null
    if (text.isEmpty()) return

    paragraphs.add(RichTextParagraph(text, currentPrefix, currentSpacing))
    pendingGap = 0f

    if (plainText.isNotEmpty()) plainText.append('\n')
    currentPrefix?.let { plainText.append(it).append(' ') }
    plainText.append(text)
  }

  private fun appendBlockText(raw: String) {
    if (raw.isBlank()) return
    if (frames.isEmpty()) beginTopLevelChild()
    beginParagraph(null)
    appendRun(raw, InlineStyle(), detectPhones = false)
    finishParagraph()
  }

  /** htmlparser2 closes an open `<p>` when a block starts and `<li>` on the next `<li>`, but only when it is innermost. */
  private fun closeParagraphIfImplied(tag: String) {
    val last = frames.lastOrNull() ?: return
    if (last.kind != Kind.PARAGRAPH) return
    val closes =
        (last.tag == "p" && tag in setOf("p", "div", "ul", "ol", "h1", "h2", "h3", "h4", "h5", "h6")) ||
            (last.tag == "li" && tag == "li")
    if (closes) popTo(frames.size - 1)
  }

  private fun popTo(index: Int) {
    if (index >= frames.size) return
    val poppedParagraph = (index until frames.size).any { frames[it].kind == Kind.PARAGRAPH }
    while (frames.size > index) frames.removeAt(frames.size - 1)
    if (poppedParagraph) finishParagraph()
  }

  private fun headingWeight(tag: String): RichTextFontWeight =
      when (tag) {
        "h1", "h2" -> if (style.fontFamily == "KantumruyPro") RichTextFontWeight.SEMIBOLD else RichTextFontWeight.BOLD
        "h3", "h4" -> RichTextFontWeight.SEMIBOLD
        else -> RichTextFontWeight.REGULAR
      }

  // MARK: Inline

  private fun openInline(tag: String, href: String?, selfClosing: Boolean) {
    when (tag) {
      "br" -> {
        append(LINE_BREAK.toString(), frames.lastOrNull()?.style ?: InlineStyle())
        return
      }
      in ignoredTags -> {
        if (!selfClosing) frames.add(Frame(Kind.IGNORED, tag))
        return
      }
    }
    if (selfClosing) return

    val base = frames.lastOrNull()?.style ?: InlineStyle()
    val next =
        when (tag) {
          "b", "strong" -> base.copy(weight = RichTextFontWeight.BOLD)
          "i", "em" -> base.copy(italic = true)
          "u" -> base.copy(underline = true)
          "s", "del" -> base.copy(strikethrough = true)
          "a" -> href?.let(::linkUrl)?.let { base.copy(link = RichTextLinkSpan(it, isPhone = false)) } ?: base
          else -> base
        }
    frames.add(Frame(Kind.INLINE, tag, next))
  }

  private fun appendRun(raw: String, inline: InlineStyle, detectPhones: Boolean) {
    if (current == null || raw.isEmpty()) return
    val text = normalizeNewlines(raw)
    if (!detectPhones) {
      append(text, inline)
      return
    }
    var cursor = 0
    for (range in RichTextPhoneDetector.matches(text)) {
      if (range.first > cursor) append(text.substring(cursor, range.first), inline)
      val number = text.substring(range.first, range.last + 1)
      append(number, inline.copy(link = RichTextLinkSpan("tel:" + number.replace(" ", ""), isPhone = true)))
      cursor = range.last + 1
    }
    if (cursor < text.length) append(text.substring(cursor), inline)
  }

  private fun append(string: String, inline: InlineStyle) {
    val out = current ?: return
    if (string.isEmpty()) return
    val start = out.length
    out.append(string)
    applyStyle(out, start, out.length, inline)
  }

  private fun applyStyle(out: SpannableStringBuilder, start: Int, end: Int, inline: InlineStyle) {
    val flags = Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
    out.setSpan(RichTextTypefaceSpan(typeface(inline.weight, inline.italic), style.fontSizePx), start, end, flags)
    inline.link?.let { out.setSpan(it, start, end, flags) }
    if (inline.underline && inline.link == null) out.setSpan(UnderlineSpan(), start, end, flags)
    if (inline.strikethrough) out.setSpan(StrikethroughSpan(), start, end, flags)
  }

  /** RN `<Text>` keeps raw newlines from the HTML source as line breaks. */
  private fun normalizeNewlines(s: String): String =
      if (s.indexOf('\r') < 0) s else s.replace("\r\n", "\n").replace('\r', '\n')
}

/**
 * Tightened phone-number pattern: no line-spanning whitespace, 8–15 digits, date shapes
 * (2024-01-15, 15-01-2024) rejected (kept in sync with the iOS detector).
 */
internal object RichTextPhoneDetector {
  private val candidate = Pattern.compile("\\+?\\d[\\d \\-]{6,}\\d")
  private val dateShape = Regex("^(\\d{4}-\\d{1,2}-\\d{1,2}|\\d{1,2}-\\d{1,2}-\\d{4})$")

  fun matches(text: String): List<IntRange> {
    var digits = 0
    for (c in text) {
      if (c in '0'..'9' && ++digits >= 8) break
    }
    if (digits < 8) return emptyList()

    val result = ArrayList<IntRange>()
    val m = candidate.matcher(text)
    while (m.find()) {
      val value = m.group()
      val count = value.count { it in '0'..'9' }
      if (count in 8..15 && !dateShape.matches(value)) result.add(m.start() until m.end())
    }
    return result
  }
}
