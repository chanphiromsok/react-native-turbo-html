#pragma once

#import <CoreGraphics/CoreGraphics.h>
#import <CoreText/CoreText.h>
#import <Foundation/Foundation.h>

#include <memory>
#include <vector>

#import "RichTextDocument.h"

NS_ASSUME_NONNULL_BEGIN

// ObjC++ port of ios/Core/RichTextLayout.swift.
namespace turbohtml {

struct RichTextPlacedLine {
  CTLineRef line; // owned (+1); released by RichTextLayout's destructor
  // `x` and the baseline `y`, in top-left (UIKit) coordinates.
  CGPoint origin;
  // Contains a link run: drawn run by run so links get `linkColor`; other lines are a
  // single CTLineDraw in the body color.
  bool hasLinks = false;
};

struct RichTextLinkRect {
  CGRect rect;
  RichTextLinkValue *link;
};

struct RichTextDecoration {
  CGRect rect;
  bool isLink;
};

// Immutable, fully laid-out text. Built off the main thread (Yoga measure), then only
// drawn on the main thread.
class RichTextLayout {
 public:
  RichTextLayout(std::vector<RichTextPlacedLine> lines, std::vector<RichTextLinkRect> links,
                 std::vector<RichTextDecoration> decorations, CGFloat width, CGFloat usedWidth, CGFloat height,
                 int lineCount, bool truncated, NSString *accessibilityText);
  ~RichTextLayout();
  RichTextLayout(const RichTextLayout &) = delete;
  RichTextLayout &operator=(const RichTextLayout &) = delete;

  static std::shared_ptr<RichTextLayout> empty();

  const std::vector<RichTextPlacedLine> &lines() const { return lines_; }
  const std::vector<RichTextLinkRect> &links() const { return links_; }
  const std::vector<RichTextDecoration> &decorations() const { return decorations_; }
  CGFloat width() const { return width_; }
  CGFloat usedWidth() const { return usedWidth_; }
  CGFloat height() const { return height_; }
  int lineCount() const { return lineCount_; }
  bool truncated() const { return truncated_; }
  NSString *accessibilityText() const { return accessibilityText_; }

  RichTextLinkValue *_Nullable linkAt(CGPoint point, CGFloat slop = 4) const;

 private:
  std::vector<RichTextPlacedLine> lines_;
  std::vector<RichTextLinkRect> links_;
  std::vector<RichTextDecoration> decorations_;
  CGFloat width_;
  CGFloat usedWidth_;
  CGFloat height_;
  int lineCount_;
  bool truncated_;
  NSString *accessibilityText_;
};

// Lays out a `RichTextDocument` with `CTTypesetter`, placing every line manually so line
// height, block spacing and truncation are exact. See ios/Core/RichTextLayout.swift for
// the full rule list; behavior must stay identical.
class RichTextLayouter {
 public:
  static std::shared_ptr<RichTextLayout> layout(const RichTextDocument &document, CGFloat width, int maxLines);
};

} // namespace turbohtml

NS_ASSUME_NONNULL_END
