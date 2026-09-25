package com.turbohtml.core

import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Paint.FontMetricsInt
import android.text.Layout
import android.text.SpannableStringBuilder
import android.text.Spanned
import android.text.StaticLayout
import android.text.TextPaint
import android.text.TextUtils
import android.text.style.LineHeightSpan
import kotlin.math.ceil
import kotlin.math.floor
import kotlin.math.max

/**
 * Exact line height with the glyphs centered in the line box — how RN `<Text lineHeight>`
 * distributes the extra leading (mirrors RN's `CustomLineHeightSpan`).
 */
internal class RichTextLineHeightSpan(private val heightPx: Int) : LineHeightSpan {
  override fun chooseHeight(text: CharSequence, start: Int, end: Int, spanstartv: Int, lineHeight: Int, fm: FontMetricsInt) {
    val leading = heightPx - (fm.descent - fm.ascent)
    fm.ascent -= ceil(leading / 2.0).toInt()
    fm.descent += floor(leading / 2.0).toInt()
    fm.top = fm.ascent
    fm.bottom = fm.descent
  }
}

/** One laid-out block: its StaticLayout plus an optional marker, at a fixed origin. */
internal class RichTextPlacedParagraph(
    val layout: StaticLayout,
    val marker: StaticLayout?,
    val x: Float,
    val y: Float,
)

/**
 * Immutable, fully laid-out text. Built during Yoga's measure (JS thread) and only drawn
 * afterwards on the main thread. Each StaticLayout owns its TextPaint, so the draw-time color
 * change never races a measure on another thread.
 */
internal class RichTextLayout(
    val paragraphs: List<RichTextPlacedParagraph>,
    val widthPx: Int,
    val heightPx: Int,
    val usedWidthPx: Int,
    val lineCount: Int,
    val truncated: Boolean,
    val accessibilityText: String,
) {
  companion object {
    val EMPTY = RichTextLayout(emptyList(), 0, 0, 0, 0, false, "")
  }

  val hasLinks: Boolean by lazy {
    paragraphs.any { p ->
      val text = p.layout.text as? Spanned
      text != null && text.getSpans(0, text.length, RichTextLinkSpan::class.java).isNotEmpty()
    }
  }

  fun draw(canvas: Canvas, bodyColor: Int, linkColor: Int) {
    for (p in paragraphs) {
      p.marker?.let {
        it.paint.color = bodyColor
        canvas.save()
        canvas.translate(0f, p.y)
        it.draw(canvas)
        canvas.restore()
      }
      p.layout.paint.color = bodyColor // plain runs use the paint's color…
      p.layout.paint.linkColor = linkColor // …and RichTextLinkSpan reads linkColor
      canvas.save()
      canvas.translate(p.x, p.y)
      p.layout.draw(canvas)
      canvas.restore()
    }
  }

  fun linkAt(x: Float, y: Float, slopPx: Float): RichTextLinkSpan? {
    for (p in paragraphs) {
      val layout = p.layout
      if (y < p.y - slopPx || y > p.y + layout.height + slopPx) continue
      val localX = x - p.x
      val localY = (y - p.y).coerceIn(0f, (layout.height - 1).toFloat().coerceAtLeast(0f))
      val line = layout.getLineForVertical(localY.toInt())
      if (localX < layout.getLineLeft(line) - slopPx || localX > layout.getLineRight(line) + slopPx) continue
      val text = layout.text as? Spanned ?: continue
      val offset = layout.getOffsetForHorizontal(line, localX)
      val spans = text.getSpans(max(0, offset - 1), offset, RichTextLinkSpan::class.java)
      if (spans.isNotEmpty()) return spans.first()
    }
    return null
  }
}

/**
 * Lays out a [RichTextDocument] as one StaticLayout per block, placed manually so block
 * spacing, list markers and a global `numberOfLines` behave like the iOS Core Text version.
 */
internal object RichTextLayouter {
  fun layout(document: RichTextDocument, style: RichTextStyle, widthPx: Int, maxLines: Int, markerGapPx: Float): RichTextLayout {
    if (widthPx <= 0 || document.paragraphs.isEmpty()) return RichTextLayout.EMPTY

    val lineHeightPx = max(1, Math.round(style.lineHeightPx))
    val limit = if (maxLines > 0) maxLines else Int.MAX_VALUE
    val placed = ArrayList<RichTextPlacedParagraph>(document.paragraphs.size)
    var y = 0f
    var lines = 0
    var usedWidth = 0f
    var truncated = false

    for ((index, paragraph) in document.paragraphs.withIndex()) {
      if (lines >= limit) {
        truncated = true
        break
      }
      if (placed.isNotEmpty()) y += paragraph.spacingBeforePx

      val marker = paragraph.prefix?.let { build(withLineHeight(it, lineHeightPx), style, widthPx, Int.MAX_VALUE) }
      val indent = marker?.let { it.getLineWidth(0) + markerGapPx } ?: 0f
      val contentWidth = max(1, (widthPx - indent).toInt())

      val remaining = limit - lines
      var text: CharSequence = withLineHeight(paragraph.text, lineHeightPx)
      var layout = build(text, style, contentWidth, remaining)
      val moreAfter = index < document.paragraphs.size - 1

      if (remaining != Int.MAX_VALUE && layout.lineCount >= remaining) {
        val last = layout.lineCount - 1
        val ellipsized = layout.getEllipsisCount(last) > 0 || layout.lineCount > remaining
        if (ellipsized) {
          truncated = true
        } else if (moreAfter) {
          // The block fits exactly but later blocks are cut: mark the cut explicitly.
          truncated = true
          val cutAt = layout.getLineEnd(last)
          val cut = SpannableStringBuilder(paragraph.text, 0, cutAt.coerceAtMost(paragraph.text.length))
          while (cut.isNotEmpty() && cut[cut.length - 1].isWhitespace()) cut.delete(cut.length - 1, cut.length)
          cut.append('…')
          text = withLineHeight(cut, lineHeightPx)
          layout = build(text, style, contentWidth, remaining)
        }
      }

      placed.add(RichTextPlacedParagraph(layout, marker, indent, y))
      for (line in 0 until layout.lineCount) usedWidth = max(usedWidth, indent + layout.getLineWidth(line))
      y += layout.height
      lines += layout.lineCount
      if (truncated) break
    }

    return RichTextLayout(
        paragraphs = placed,
        widthPx = widthPx,
        heightPx = ceil(y).toInt(),
        usedWidthPx = ceil(usedWidth).toInt().coerceAtMost(widthPx),
        lineCount = lines,
        truncated = truncated,
        accessibilityText = document.plainText,
    )
  }

  private fun withLineHeight(text: CharSequence, lineHeightPx: Int): CharSequence {
    val out = SpannableStringBuilder(text)
    out.setSpan(RichTextLineHeightSpan(lineHeightPx), 0, out.length, Spanned.SPAN_INCLUSIVE_INCLUSIVE)
    return out
  }

  private fun build(text: CharSequence, style: RichTextStyle, widthPx: Int, maxLines: Int): StaticLayout {
    // A fresh paint per layout: the view sets its color at draw time on the main thread.
    val paint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply { textSize = style.fontSizePx }
    val builder =
        StaticLayout.Builder.obtain(text, 0, text.length, paint, widthPx)
            .setAlignment(Layout.Alignment.ALIGN_NORMAL)
            .setIncludePad(false)
            .setLineSpacing(0f, 1f)
            .setBreakStrategy(Layout.BREAK_STRATEGY_HIGH_QUALITY)
            .setHyphenationFrequency(Layout.HYPHENATION_FREQUENCY_NONE)
    if (maxLines != Int.MAX_VALUE) {
      builder.setMaxLines(maxLines).setEllipsize(TextUtils.TruncateAt.END)
    }
    return builder.build()
  }
}
