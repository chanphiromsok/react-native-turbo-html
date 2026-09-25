#pragma once

#import <CoreGraphics/CoreGraphics.h>
#import <Foundation/Foundation.h>

#include <memory>

#import "RichTextLayout.h"

// ObjC++ port of ios/Core/RichTextEngine.swift.
namespace turbohtml {

// Parse + layout cache shared by Yoga's measure pass (`TurboHtmlMeasure`, any thread) and
// the component view (main thread). Measuring a row stores its layout, so the view drawing
// that row at the same width is a cache hit and does no text work.
class RichTextEngine {
 public:
  static RichTextEngine &shared();

  // Takes raw UTF-8 bytes rather than `NSString *` so a cache *hit* never has to touch
  // Foundation's string storage: for non-ASCII content (Khmer, emoji, ...) an `NSString`
  // is usually backed by UTF-16 internally, so recovering UTF-8 bytes from one means a
  // transcode + allocation on every call. The real caller (`TurboHtmlMeasure`) already has
  // the raw bytes from the ShadowNode's `std::string` props, so this keeps the hot path
  // (hash the bytes, look up, done) allocation-free on a hit.
  std::shared_ptr<RichTextLayout> layout(const char *html, size_t htmlLength, const RichTextStyle &style,
                                         CGFloat width, int maxLines);
  // Convenience overload for callers that only have an `NSString` (the component view,
  // which redraws far less often than Yoga re-measures); this one may need to copy.
  std::shared_ptr<RichTextLayout> layout(NSString *html, const RichTextStyle &style, CGFloat width, int maxLines);
  void clear();

 private:
  RichTextEngine();
  RichTextEngine(const RichTextEngine &) = delete;
};

} // namespace turbohtml

// Called from `TurboHtmlViewShadowNode::measureContent` (C++, Yoga's layout thread) on iOS.
// Returns the height; writes the width actually used by the text to `outUsedWidth`. Keep
// this signature in sync with cpp/react/renderer/components/TurboHtmlViewSpec/TurboHtmlViewShadowNode.cpp.
extern "C" double TurboHtmlMeasure(const char *html, long htmlLength, const char *fontFamily, double fontSize,
                                    double lineHeight, int numberOfLines, bool detectPhoneNumbers,
                                    int headingFontWeight, double width, double fontScale,
                                    double *outUsedWidth);
