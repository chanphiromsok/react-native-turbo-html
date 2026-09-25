package com.turbohtml

import android.graphics.Color
import com.facebook.react.module.annotations.ReactModule
import com.facebook.react.uimanager.SimpleViewManager
import com.facebook.react.uimanager.ThemedReactContext
import com.facebook.react.uimanager.ViewManagerDelegate
import com.facebook.react.uimanager.annotations.ReactProp
import com.facebook.react.viewmanagers.TurboHtmlViewManagerInterface
import com.facebook.react.viewmanagers.TurboHtmlViewManagerDelegate

@ReactModule(name = TurboHtmlViewManager.NAME)
class TurboHtmlViewManager : SimpleViewManager<TurboHtmlView>(),
  TurboHtmlViewManagerInterface<TurboHtmlView> {
  private val mDelegate: ViewManagerDelegate<TurboHtmlView>

  init {
    mDelegate = TurboHtmlViewManagerDelegate(this)
  }

  override fun getDelegate(): ViewManagerDelegate<TurboHtmlView>? {
    return mDelegate
  }

  override fun getName(): String {
    return NAME
  }

  public override fun createViewInstance(context: ThemedReactContext): TurboHtmlView {
    return TurboHtmlView(context)
  }

  @ReactProp(name = "color")
  override fun setColor(view: TurboHtmlView?, color: Int?) {
    view?.setBackgroundColor(color ?: Color.TRANSPARENT)
  }

  companion object {
    const val NAME = "TurboHtmlView"
  }
}
