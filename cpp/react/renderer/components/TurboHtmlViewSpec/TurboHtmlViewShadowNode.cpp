#include "TurboHtmlViewShadowNode.h"

#include <react/renderer/core/LayoutConstraints.h>
#include <react/renderer/core/LayoutContext.h>

#include <cmath>

#ifndef ANDROID
// Implemented in Objective-C++ (ios/Core/RichTextEngine.mm, `extern "C"`). Thread-safe:
// parses and lays out with Core Text, caching the result for the view to draw.
extern "C" double TurboHtmlMeasure(
    const char *html,
    long htmlLength,
    const char *fontFamily,
    double fontSize,
    double lineHeight,
    int numberOfLines,
    bool detectPhoneNumbers,
    double width,
    double fontScale,
    double *outUsedWidth);
#endif

namespace facebook::react {

extern const char TurboHtmlViewComponentName[] = "TurboHtmlView";

#ifdef ANDROID

void TurboHtmlViewShadowNode::setMeasurementsManager(
    const std::shared_ptr<TurboHtmlMeasurementsManager> &measurementsManager) {
  ensureUnsealed();
  measurementsManager_ = measurementsManager;
}

Size TurboHtmlViewShadowNode::measureContent(
    const LayoutContext & /*layoutContext*/,
    const LayoutConstraints &layoutConstraints) const {
  const auto &props = getConcreteProps();
  if (props.html.empty() || !measurementsManager_) {
    return layoutConstraints.clamp({0, 0});
  }
  // Font scale is applied on the Kotlin side (SP units), matching RN <Text>.
  return measurementsManager_->measure(getSurfaceId(), props, layoutConstraints);
}

#else

Size TurboHtmlViewShadowNode::measureContent(
    const LayoutContext &layoutContext,
    const LayoutConstraints &layoutConstraints) const {
  const auto &props = getConcreteProps();
  if (props.html.empty()) {
    return layoutConstraints.clamp({0, 0});
  }

  const Float maxWidth = layoutConstraints.maximumSize.width;
  const bool widthIsBounded = std::isfinite(maxWidth);
  // Unbounded width (e.g. inside a horizontal ScrollView): lay out as one long line.
  const double width = widthIsBounded ? maxWidth : 100000.0;

  double usedWidth = 0;
  const double height = TurboHtmlMeasure(
      props.html.c_str(),
      static_cast<long>(props.html.size()),
      props.fontFamily.c_str(),
      props.fontSize,
      props.lineHeight,
      props.numberOfLines,
      props.detectPhoneNumbers,
      width,
      layoutContext.fontSizeMultiplier,
      &usedWidth);

  // Fill the available width like a block (RenderHtml's <Text> rows stretch too), so the
  // view draws at exactly the width it was measured at.
  const Float resultWidth = widthIsBounded ? maxWidth : static_cast<Float>(std::ceil(usedWidth));
  return layoutConstraints.clamp({resultWidth, static_cast<Float>(height)});
}

#endif

} // namespace facebook::react
