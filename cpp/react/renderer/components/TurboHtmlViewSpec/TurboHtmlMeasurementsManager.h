#pragma once

#ifdef ANDROID

#include <react/renderer/components/TurboHtmlViewSpec/Props.h>
#include <react/renderer/core/LayoutConstraints.h>
#include <react/utils/ContextContainer.h>

namespace facebook::react {

/*
 * Android measurement bridge (same pattern as RN's AndroidSwitch/AndroidProgressBar):
 * `measureContent` → JNI `FabricUIManager.measure(...)` → Kotlin
 * `TurboHtmlViewManager.measure(...)`, which parses + lays out with StaticLayout and
 * caches the result for the view to draw.
 */
class TurboHtmlMeasurementsManager {
 public:
  explicit TurboHtmlMeasurementsManager(const std::shared_ptr<const ContextContainer> &contextContainer)
      : contextContainer_(contextContainer) {}

  Size measure(SurfaceId surfaceId, const TurboHtmlViewProps &props, const LayoutConstraints &layoutConstraints)
      const;

 private:
  const std::shared_ptr<const ContextContainer> contextContainer_;
};

} // namespace facebook::react

#endif // ANDROID
