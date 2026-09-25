package com.turbohtml

import android.annotation.SuppressLint
import android.content.Context
import android.content.res.Configuration
import android.graphics.Canvas
import android.view.MotionEvent
import android.view.View
import com.facebook.react.bridge.ReactContext
import com.facebook.react.uimanager.PixelUtil
import com.facebook.react.uimanager.UIManagerHelper
import com.facebook.react.uimanager.events.NativeGestureUtil
import com.turbohtml.core.RichTextEngine
import com.turbohtml.core.RichTextLayout
import com.turbohtml.core.RichTextLinkSpan

/**
 * Draws a cached [RichTextLayout]. Yoga already measured this exact (html, style, width) in the
 * ShadowNode → `TurboHtmlViewManager.measure`, so the engine lookup here is a cache hit:
 * no parsing or line breaking on the main thread in the normal path.
 */
@SuppressLint("ViewConstructor")
class TurboHtmlView(context: Context) : View(context) {
  private var html = ""
  private var fontFamily = ""
  private var fontSize = 14f
  private var lineHeight = 0f
  private var numberOfLines = 0
  private var detectPhoneNumbers = true
  private var headingFontWeight = 700

  /** Body / link colors; null = the theme's `textColorPrimary` / `textColorLink`. Draw-only. */
  private var textColor: Int? = null
  private var linkColor: Int? = null
  private var themeColors: Pair<Int, Int>? = null
  private var propsDirty = true

  private var layout: RichTextLayout = RichTextLayout.EMPTY
  private var pressedLink: RichTextLinkSpan? = null

  fun setHtml(value: String?) = update { html = value.orEmpty() }

  fun setFontFamily(value: String?) = update { fontFamily = value.orEmpty() }

  fun setFontSize(value: Float) = update { fontSize = value }

  fun setLineHeight(value: Float) = update { lineHeight = value }

  fun setNumberOfLines(value: Int) = update { numberOfLines = value }

  fun setDetectPhoneNumbers(value: Boolean) = update { detectPhoneNumbers = value }

  fun setHeadingFontWeight(value: Int) = update { headingFontWeight = value }

  // Colors never affect layout: they only redraw.
  fun setTextColor(value: Int?) {
    if (value == textColor) return
    textColor = value
    invalidate()
  }

  fun setLinkColor(value: Int?) {
    if (value == linkColor) return
    linkColor = value
    invalidate()
  }

  private inline fun update(block: () -> Unit) {
    block()
    propsDirty = true
  }

  /** Called once per props transaction (`onAfterUpdateTransaction`). */
  fun commitProps() {
    if (!propsDirty) return
    propsDirty = false
    relayout()
  }

  /**
   * Called before the view goes back into the recycling pool. A recycled view only receives
   * the props present in its next props map (props left at their JS default are not sent),
   * so every prop must return to its default here or it would leak from the previous row.
   */
  fun reset() {
    html = ""
    fontFamily = ""
    fontSize = 14f
    lineHeight = 0f
    numberOfLines = 0
    detectPhoneNumbers = true
    headingFontWeight = 700
    textColor = null
    linkColor = null
    propsDirty = true
    pressedLink = null
    layout = RichTextLayout.EMPTY
    contentDescription = null
    invalidate()
  }

  override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
    super.onSizeChanged(w, h, oldw, oldh)
    if (w != oldw) relayout()
  }

  private fun relayout() {
    val next =
        RichTextEngine.layout(
            html,
            TurboHtmlViewManager.styleFor(fontFamily, fontSize, lineHeight, detectPhoneNumbers, headingFontWeight),
            width,
            numberOfLines,
            TurboHtmlViewManager.markerGapPx(),
            context.assets,
        )
    if (next === layout) return
    layout = next
    contentDescription = next.accessibilityText.ifEmpty { null }
    invalidate()
  }

  override fun onDraw(canvas: Canvas) {
    super.onDraw(canvas)
    val defaults = themeColors ?: resolveThemeColors().also { themeColors = it }
    layout.draw(canvas, textColor ?: defaults.first, linkColor ?: defaults.second)
  }

  override fun onConfigurationChanged(newConfig: Configuration) {
    super.onConfigurationChanged(newConfig)
    themeColors = null // re-resolve theme defaults (light/dark); colors only live in onDraw
    invalidate()
  }

  private fun resolveThemeColors(): Pair<Int, Int> {
    val night =
        (resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK) == Configuration.UI_MODE_NIGHT_YES
    val attrs = context.obtainStyledAttributes(intArrayOf(android.R.attr.textColorPrimary, android.R.attr.textColorLink))
    try {
      val body = attrs.getColorStateList(0)?.defaultColor ?: if (night) 0xFFFFFFFF.toInt() else 0xFF000000.toInt()
      val link = attrs.getColorStateList(1)?.defaultColor ?: if (night) 0xFF8AB4F8.toInt() else 0xFF1A73E8.toInt()
      return body to link
    } finally {
      attrs.recycle()
    }
  }

  // MARK: Links

  /**
   * Only claims the touch when it starts on a link: then JS's responder is cancelled
   * (NativeGestureUtil, as ScrollView does) so the parent Pressable doesn't also fire.
   * Taps elsewhere are left entirely to the parent Pressable.
   */
  @SuppressLint("ClickableViewAccessibility")
  override fun onTouchEvent(event: MotionEvent): Boolean {
    if (!layout.hasLinks) return false
    val slop = PixelUtil.toPixelFromDIP(4f)
    when (event.actionMasked) {
      MotionEvent.ACTION_DOWN -> {
        pressedLink = layout.linkAt(event.x, event.y, slop) ?: return false
        NativeGestureUtil.notifyNativeGestureStarted(this, event)
        return true
      }
      MotionEvent.ACTION_UP -> {
        val link = pressedLink
        pressedLink = null
        NativeGestureUtil.notifyNativeGestureEnded(this, event)
        if (link != null && layout.linkAt(event.x, event.y, slop) === link) dispatchLinkPress(link)
        return link != null
      }
      MotionEvent.ACTION_CANCEL -> {
        if (pressedLink != null) NativeGestureUtil.notifyNativeGestureEnded(this, event)
        pressedLink = null
        return false
      }
    }
    return pressedLink != null
  }

  private fun dispatchLinkPress(link: RichTextLinkSpan) {
    val reactContext = context as? ReactContext ?: return
    val dispatcher = UIManagerHelper.getEventDispatcherForReactTag(reactContext, id) ?: return
    dispatcher.dispatchEvent(
        LinkPressEvent(UIManagerHelper.getSurfaceId(this), id, link.url, if (link.isPhone) "phone" else "link"))
  }
}
