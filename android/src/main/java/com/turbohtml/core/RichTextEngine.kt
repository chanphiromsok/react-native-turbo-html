package com.turbohtml.core

import android.content.res.AssetManager
import android.graphics.Typeface
import android.util.LruCache
import com.facebook.react.common.assets.ReactFontManager
import kotlin.math.abs

/**
 * Parse + layout cache shared by Yoga's measure (`TurboHtmlViewManager.measure`, JS
 * thread) and the view (main thread): measuring a row stores its layout, so the view drawing
 * that row is a cache hit and does no text work. Sized for a feed (see the iOS engine).
 */
internal object RichTextEngine {
  private data class DocumentKey(val html: String, val style: RichTextStyle)

  private class Entry(val document: RichTextDocument) {
    private val layouts = ArrayList<Pair<Int, RichTextLayout>>(MAX_LAYOUTS) // (maxLines, layout)

    @Synchronized
    fun layout(widthPx: Int, maxLines: Int, compute: () -> RichTextLayout): RichTextLayout {
      // Yoga's width (float dp → px) and the view's integer pixel width can differ by 1px.
      layouts.firstOrNull { it.first == maxLines && abs(it.second.widthPx - widthPx) <= 1 }?.let { return it.second }
      val computed = compute()
      if (layouts.size >= MAX_LAYOUTS) layouts.clear() // a feed renders at one width
      layouts.add(maxLines to computed)
      return computed
    }

    companion object {
      const val MAX_LAYOUTS = 2
    }
  }

  private val documents = LruCache<DocumentKey, Entry>(100)

  fun layout(
      html: String,
      style: RichTextStyle,
      widthPx: Int,
      maxLines: Int,
      markerGapPx: Float,
      assets: AssetManager?,
  ): RichTextLayout {
    if (html.isEmpty() || widthPx <= 0) return RichTextLayout.EMPTY
    val key = DocumentKey(html, style)
    val entry =
        documents.get(key)
            ?: Entry(RichTextDocumentBuilder.build(html, style) { weight, italic -> typeface(style.fontFamily, weight, italic, assets) })
                .also { documents.put(key, it) }
    return entry.layout(widthPx, maxLines) { RichTextLayouter.layout(entry.document, style, widthPx, maxLines, markerGapPx) }
  }

  fun clear() = documents.evictAll()

  /** Custom font families registered by expo-font (`Figtree`, `KantumruyPro` XML families); synthesizes italics. */
  private fun typeface(family: String, weight: RichTextFontWeight, italic: Boolean, assets: AssetManager?): Typeface =
      ReactFontManager.getInstance().getTypeface(family, weight.value, italic, assets)
}
