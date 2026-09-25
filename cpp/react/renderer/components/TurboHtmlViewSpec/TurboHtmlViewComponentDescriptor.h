#pragma once

#include "TurboHtmlViewShadowNode.h"
#include <react/renderer/core/ConcreteComponentDescriptor.h>

namespace facebook::react {

#ifdef ANDROID

class TurboHtmlViewComponentDescriptor final
    : public ConcreteComponentDescriptor<TurboHtmlViewShadowNode> {
 public:
  explicit TurboHtmlViewComponentDescriptor(const ComponentDescriptorParameters &parameters)
      : ConcreteComponentDescriptor(parameters),
        measurementsManager_(std::make_shared<TurboHtmlMeasurementsManager>(contextContainer_)) {}

  void adopt(ShadowNode &shadowNode) const override {
    ConcreteComponentDescriptor::adopt(shadowNode);
    static_cast<TurboHtmlViewShadowNode &>(shadowNode).setMeasurementsManager(measurementsManager_);
  }

 private:
  const std::shared_ptr<TurboHtmlMeasurementsManager> measurementsManager_;
};

#else

using TurboHtmlViewComponentDescriptor = ConcreteComponentDescriptor<TurboHtmlViewShadowNode>;

#endif

} // namespace facebook::react
