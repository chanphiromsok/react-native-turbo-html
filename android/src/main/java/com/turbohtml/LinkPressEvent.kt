package com.turbohtml

import com.facebook.react.bridge.Arguments
import com.facebook.react.bridge.WritableMap
import com.facebook.react.uimanager.events.Event

/** `onLinkPress` — `type` is "link" for `<a href>`, "phone" for a detected number. */
internal class LinkPressEvent(surfaceId: Int, viewTag: Int, private val url: String, private val type: String) :
    Event<LinkPressEvent>(surfaceId, viewTag) {
  override fun getEventName(): String = EVENT_NAME

  override fun getEventData(): WritableMap =
      Arguments.createMap().apply {
        putString("url", url)
        putString("type", type)
      }

  companion object {
    const val EVENT_NAME = "topLinkPress"
  }
}
