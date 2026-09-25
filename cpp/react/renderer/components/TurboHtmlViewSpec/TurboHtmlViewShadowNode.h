#pragma once

#include <jsi/jsi.h>
#include <react/renderer/components/TurboHtmlViewSpec/EventEmitters.h>
#include <react/renderer/components/TurboHtmlViewSpec/Props.h>
#include <react/renderer/components/view/ConcreteViewShadowNode.h>

#ifdef ANDROID
#include "TurboHtmlMeasurementsManager.h"
#endif

namespace facebook::react {

JSI_EXPORT extern const char TurboHtmlViewComponentName[];

/*
 * ShadowNode for <TurboHtmlView>. A measurable Yoga leaf: during layout Yoga calls
 * `measureContent` with the real available width, and the native text engine returns
 * the exact height — no JS measuring, no height passed as a style, no post-mount resize.
 *
 * iOS: calls the native engine directly through the C function `TurboHtmlMeasure`
 * (Objective-C++, ios/Core/RichTextEngine.mm).
 * Android: goes through `TurboHtmlMeasurementsManager` (JNI → Kotlin ViewManager).
 */
class JSI_EXPORT TurboHtmlViewShadowNode final : public ConcreteViewShadowNode<
                                                    TurboHtmlViewComponentName,
                                                    TurboHtmlViewProps,
                                                    TurboHtmlViewEventEmitter> {
 public:
  using ConcreteViewShadowNode::ConcreteViewShadowNode;

  static ShadowNodeTraits BaseTraits() {
    auto traits = ConcreteViewShadowNode::BaseTraits();
    traits.set(ShadowNodeTraits::Trait::LeafYogaNode);
    traits.set(ShadowNodeTraits::Trait::MeasurableYogaNode);
    return traits;
  }

  Size measureContent(const LayoutContext &layoutContext, const LayoutConstraints &layoutConstraints) const override;

#ifdef ANDROID
  void setMeasurementsManager(const std::shared_ptr<TurboHtmlMeasurementsManager> &measurementsManager);

 private:
  std::shared_ptr<TurboHtmlMeasurementsManager> measurementsManager_;
#endif
};

} // namespace facebook::react
