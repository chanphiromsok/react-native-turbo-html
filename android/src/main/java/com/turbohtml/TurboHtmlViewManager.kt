package com.turbohtml

import android.content.Context
import com.facebook.react.bridge.ReadableMap
import com.facebook.react.module.annotations.ReactModule
import com.facebook.react.uimanager.PixelUtil
import com.facebook.react.uimanager.SimpleViewManager
import com.facebook.react.uimanager.ThemedReactContext
import com.facebook.react.uimanager.ViewManagerDelegate
import com.facebook.react.viewmanagers.TurboHtmlViewManagerDelegate
import com.facebook.react.viewmanagers.TurboHtmlViewManagerInterface
import com.facebook.yoga.YogaMeasureMode
import com.facebook.yoga.YogaMeasureOutput
import com.turbohtml.core.RichTextEngine
import com.turbohtml.core.RichTextStyle
import kotlin.math.floor

@ReactModule(name = TurboHtmlViewManager.NAME)
class TurboHtmlViewManager :
    SimpleViewManager<TurboHtmlView>(), TurboHtmlViewManagerInterface<TurboHtmlView> {
  private val delegate: ViewManagerDelegate<TurboHtmlView> = TurboHtmlViewManagerDelegate(this)

  override fun getDelegate(): ViewManagerDelegate<TurboHtmlView> = delegate

  init {
    // Opt into Fabric view recycling. Only takes effect when the app enables the
    // `enableViewRecycling` feature flag (off by default on Android); `reset()` in
    // `prepareToRecycleView` restores every prop so reuse is safe.
    setupViewRecycling()
  }

  override fun getName(): String = NAME

  override fun createViewInstance(context: ThemedReactContext): TurboHtmlView = TurboHtmlView(context)

  override fun setHtml(view: TurboHtmlView, value: String?) = view.setHtml(value)

  override fun setFontFamily(view: TurboHtmlView, value: String?) = view.setFontFamily(value)

  override fun setFontSize(view: TurboHtmlView, value: Float) = view.setFontSize(value)

  override fun setLineHeight(view: TurboHtmlView, value: Float) = view.setLineHeight(value)

  override fun setNumberOfLines(view: TurboHtmlView, value: Int) = view.setNumberOfLines(value)

  override fun setDetectPhoneNumbers(view: TurboHtmlView, value: Boolean) = view.setDetectPhoneNumbers(value)

  override fun setHeadingFontWeight(view: TurboHtmlView, value: Int) = view.setHeadingFontWeight(value)

  override fun setColor(view: TurboHtmlView, value: Int?) = view.setTextColor(value)

  override fun setLinkColor(view: TurboHtmlView, value: Int?) = view.setLinkColor(value)

  override fun onAfterUpdateTransaction(view: TurboHtmlView) {
    super.onAfterUpdateTransaction(view)
    view.commitProps()
  }

  override fun prepareToRecycleView(reactContext: ThemedReactContext, view: TurboHtmlView): TurboHtmlView? {
    view.reset()
    return super.prepareToRecycleView(reactContext, view)
  }

  override fun getExportedCustomDirectEventTypeConstants(): Map<String, Any> =
      mapOf(LinkPressEvent.EVENT_NAME to mapOf("registrationName" to "onLinkPress"))

  /**
   * Called by the C++ ShadowNode during Yoga layout (via `FabricUIManager.measure`, JS
   * thread). Widths arrive in px; the result is returned in DIP. The layout is cached, so the
   * view drawing this row later is a cache hit.
   */
  override fun measure(
      context: Context,
      localData: ReadableMap?,
      props: ReadableMap?,
      state: ReadableMap?,
      width: Float,
      widthMode: YogaMeasureMode,
      height: Float,
      heightMode: YogaMeasureMode,
      attachmentsPositions: FloatArray?,
  ): Long {
    val html = props?.takeIf { it.hasKey("html") }?.getString("html").orEmpty()
    if (html.isEmpty()) return YogaMeasureOutput.make(0f, 0f)

    val style =
        styleFor(
            props?.getStringOr("fontFamily", "") ?: "",
            props?.getDoubleOr("fontSize", 14.0)?.toFloat() ?: 14f,
            props?.getDoubleOr("lineHeight", 0.0)?.toFloat() ?: 0f,
            props?.takeIf { it.hasKey("detectPhoneNumbers") }?.getBoolean("detectPhoneNumbers") ?: true,
            props?.takeIf { it.hasKey("headingFontWeight") }?.getInt("headingFontWeight") ?: 700,
        )
    val numberOfLines = props?.takeIf { it.hasKey("numberOfLines") }?.getInt("numberOfLines") ?: 0
    val bounded = widthMode != YogaMeasureMode.UNDEFINED && width.isFinite()
    val widthPx = if (bounded) floor(width).toInt() else 100_000

    val layout = RichTextEngine.layout(html, style, widthPx, numberOfLines, markerGapPx(), context.assets)
    val resultWidthPx = if (bounded) width else layout.usedWidthPx.toFloat()
    return YogaMeasureOutput.make(PixelUtil.toDIPFromPixel(resultWidthPx), PixelUtil.toDIPFromPixel(layout.heightPx.toFloat()))
  }

  companion object {
    const val NAME = "TurboHtmlView"

    /** Sizes are SP like RN `<Text>` (allowFontScaling): scaled by the system font size. */
    internal fun styleFor(
        fontFamily: String,
        fontSize: Float,
        lineHeight: Float,
        detectPhoneNumbers: Boolean,
        headingFontWeight: Int,
    ): RichTextStyle {
      val size = if (fontSize > 0) fontSize else 14f
      // 0 = the font's natural line height (≈ 1.2 × size), matching iOS.
      val height = if (lineHeight > 0) lineHeight else kotlin.math.ceil(size * 1.2f)
      return RichTextStyle(
          fontFamily = fontFamily,
          fontSizePx = PixelUtil.toPixelFromSP(size),
          lineHeightPx = PixelUtil.toPixelFromSP(height),
          detectPhoneNumbers = detectPhoneNumbers,
          headingFontWeight = if (headingFontWeight > 0) headingFontWeight else 700,
          blockGapPx = PixelUtil.toPixelFromDIP(4f),
      )
    }

    internal fun markerGapPx(): Float = PixelUtil.toPixelFromDIP(4f)

    private fun ReadableMap.getStringOr(key: String, fallback: String) =
        if (hasKey(key) && !isNull(key)) getString(key) ?: fallback else fallback

    private fun ReadableMap.getDoubleOr(key: String, fallback: Double) =
        if (hasKey(key) && !isNull(key)) getDouble(key) else fallback
  }
}
