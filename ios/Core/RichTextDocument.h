#pragma once

#import <CoreGraphics/CoreGraphics.h>
#import <CoreText/CoreText.h>
#import <Foundation/Foundation.h>

#include <memory>
#include <string>
#include <vector>

#import "RichTextFonts.h"

NS_ASSUME_NONNULL_BEGIN

// Value of `RichTextAttribute.link`. Declared at global scope: Objective-C `@interface`
// blocks cannot be nested inside a C++ namespace.
@interface RichTextLinkValue : NSObject
@property(nonatomic, strong, readonly) NSString *url;
@property(nonatomic, readonly) BOOL isPhone;
- (instancetype)initWithUrl:(NSString *)url isPhone:(BOOL)isPhone;
@end

// ObjC++ port of ios/Core/RichTextDocument.swift.
namespace turbohtml {

// Layout-affecting style. Color is not here: body text takes the fill color at draw time.
struct RichTextStyle {
  // Family name ("Inter", "Kantumruy Pro") or PostScript name ("Figtree-Regular"); empty =
  // the system font. Resolved like RN `<Text>` (see RichTextFonts).
  NSString *fontFamily = @"";
  CGFloat fontSize = 14;
  CGFloat lineHeight = 20;
  bool detectPhoneNumbers = true;
  // Weight for h1/h2 (h3/h4 use min(this, 600)); 100–900 like CSS.
  int headingFontWeight = 700;

  bool operator==(const RichTextStyle &other) const {
    return fontSize == other.fontSize && lineHeight == other.lineHeight &&
        detectPhoneNumbers == other.detectPhoneNumbers && headingFontWeight == other.headingFontWeight &&
        [fontFamily isEqualToString:other.fontFamily];
  }
  bool operator!=(const RichTextStyle &other) const { return !(*this == other); }

  // Applies Dynamic Type the way RN `<Text>` does (`allowFontScaling` defaults to true):
  // both font size and line height scale by the surface's `fontSizeMultiplier`.
  // `lineHeight <= 0` means the font's natural line height (≈ 1.2 × size, like RN's default).
  static RichTextStyle scaled(NSString *fontFamily, double fontSize, double lineHeight, bool detectPhoneNumbers,
                              int headingFontWeight, double fontScale);
};

namespace RichTextAttribute {
extern NSString *const Link;
extern NSString *const Underline;
extern NSString *const Strikethrough;
// kCTFontAttributeName and kCTForegroundColorFromContextAttributeName are used directly.
// No color is ever stored in the text: every run takes the context's fill color, which the
// canvas sets per run at draw time (body `color` or `linkColor`). So colors — including
// dynamic light/dark ones — can change without re-parsing or re-laying out.
} // namespace RichTextAttribute

// One block of text: a `<p>`/`<h*>`/`<li>` row, or bare text at block level.
struct RichTextParagraph {
  // Content only; `<br>` and raw newlines are U+2028 (hard line break inside the block).
  NSAttributedString *text;
  // List marker ("•" / "1.") drawn in its own column, like RenderHtml's flex row.
  NSAttributedString *prefix; // nullable
  CGFloat lineHeight;
  // Space above this block when it isn't the first one drawn (RenderHtml's `gap-1`).
  CGFloat spacingBefore;
  // Has a link, underline or strikethrough run: only then does layout collect run
  // geometry (link hit rects, decoration rects).
  bool hasDecorations;
};

class RichTextDocument {
 public:
  RichTextDocument(std::vector<RichTextParagraph> paragraphs, NSString *plainText)
      : paragraphs_(std::move(paragraphs)), plainText_(plainText) {}

  const std::vector<RichTextParagraph> &paragraphs() const { return paragraphs_; }
  NSString *plainText() const { return plainText_; }

 private:
  std::vector<RichTextParagraph> paragraphs_;
  NSString *plainText_;
};

// Builds a `RichTextDocument` from HTML with the same rules as a typical RenderHtml-style
// component, so switching a call site is visually neutral. See the Swift source
// (ios/Core/RichTextDocument.swift in react-native-turbo-html-p) for the full rule list;
// behavior must stay identical.
class RichTextDocumentBuilder {
 public:
  static std::shared_ptr<RichTextDocument> build(const char *html, size_t htmlLength, const RichTextStyle &style);

  static NSString *_Nullable linkURL(NSString *href);
};

// RenderHtml's `/(\+?[\d][\d\s\-]{6,}[\d])/`, tightened: no line-spanning whitespace,
// 8–15 digits, and date shapes (2024-01-15, 15-01-2024) are rejected.
class RichTextPhoneDetector {
 public:
  // Returns UTF-16 (NSString) ranges of phone-shaped matches within `text`.
  static std::vector<NSRange> matches(NSString *text);

  // `tel:` URL for a matched number: digits only (Khmer digits mapped to ASCII), keeping a
  // leading "+"; separators — including invisible ones — are dropped.
  static NSString *telURL(NSString *number);
};

} // namespace turbohtml

NS_ASSUME_NONNULL_END
