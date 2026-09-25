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
import com.turbohtml.core.RichTextColors
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
  private var fontFamily = "Figtree"
  private var fontSize = 14f
  private var lineHeight = 20f
  private var numberOfLines = 0
  private var detectPhoneNumbers = true
  private var propsDirty = true

  private var layout: RichTextLayout = RichTextLayout.EMPTY
  private var pressedLink: RichTextLinkSpan? = null

  fun setHtml(value: String?) = update { html = value.orEmpty() }

  fun setFontFamily(value: String?) = update { fontFamily = value?.takeIf { it.isNotEmpty() } ?: "Figtree" }

  fun setFontSize(value: Float) = update { fontSize = value }

  fun setLineHeight(value: Float) = update { lineHeight = value }

  fun setNumberOfLines(value: Int) = update { numberOfLines = value }

  fun setDetectPhoneNumbers(value: Boolean) = update { detectPhoneNumbers = value }

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

  fun reset() {
    html = ""
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
            TurboHtmlViewManager.styleFor(fontFamily, fontSize, lineHeight, detectPhoneNumbers),
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
    layout.draw(canvas, bodyColor())
  }

  override fun onConfigurationChanged(newConfig: Configuration) {
    super.onConfigurationChanged(newConfig)
    invalidate() // color only lives in onDraw, so a theme switch never re-lays out
  }

  private fun bodyColor(): Int {
    val night = resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK
    return if (night == Configuration.UI_MODE_NIGHT_YES) RichTextColors.BODY_DARK else RichTextColors.BODY_LIGHT
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
