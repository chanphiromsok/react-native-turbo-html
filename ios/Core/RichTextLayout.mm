#import "RichTextLayout.h"

#include <algorithm>
#include <cmath>

namespace turbohtml {

namespace {
constexpr CGFloat kMarkerGap = 4;
constexpr unichar kLineSeparator = 0x2028;

// RAII guard releasing a CF object when it goes out of scope (including a labeled break
// out of a nested loop), so a `CTTypesetterCreateWithAttributedString` per paragraph is
// always released exactly once regardless of which path exits the loop body.
template <typename T>
class CFScoped {
 public:
  explicit CFScoped(T ref) : ref_(ref) {}
  ~CFScoped() {
    if (ref_) CFRelease(ref_);
  }
  CFScoped(const CFScoped &) = delete;
  CFScoped &operator=(const CFScoped &) = delete;
  operator T() const { return ref_; }

 private:
  T ref_;
};

} // namespace

RichTextLayout::RichTextLayout(std::vector<RichTextPlacedLine> lines, std::vector<RichTextLinkRect> links,
                               std::vector<RichTextDecoration> decorations, CGFloat width, CGFloat usedWidth,
                               CGFloat height, int lineCount, bool truncated, NSString *accessibilityText)
    : lines_(std::move(lines)),
      links_(std::move(links)),
      decorations_(std::move(decorations)),
      width_(width),
      usedWidth_(usedWidth),
      height_(height),
      lineCount_(lineCount),
      truncated_(truncated),
      accessibilityText_(accessibilityText) {}

RichTextLayout::~RichTextLayout() {
  for (auto &placed : lines_) {
    if (placed.line) CFRelease(placed.line);
  }
}

std::shared_ptr<RichTextLayout> RichTextLayout::empty() {
  static std::shared_ptr<RichTextLayout> instance = std::make_shared<RichTextLayout>(
      std::vector<RichTextPlacedLine>{}, std::vector<RichTextLinkRect>{}, std::vector<RichTextDecoration>{}, 0, 0, 0,
      0, false, @"");
  return instance;
}

RichTextLinkValue *RichTextLayout::linkAt(CGPoint point, CGFloat slop) const {
  for (const auto &entry : links_) {
    CGRect inset = CGRectInset(entry.rect, -slop, -slop);
    if (CGRectContainsPoint(inset, point)) return entry.link;
  }
  return nil;
}

namespace {

struct Builder {
  std::vector<RichTextPlacedLine> lines;
  std::vector<RichTextLinkRect> links;
  std::vector<RichTextDecoration> decorations;
  CGFloat y = 0;
  CGFloat usedWidth = 0;
  int lineCount = 0;
  bool truncated = false;

  // Returns whether the line contains a link run.
  bool collectRunGeometry(CTLineRef line, CGFloat x, CGFloat top, CGFloat baseline, CGFloat lineHeight) {
    bool hasLinks = false;
    // Read the CFArray directly: bridging to an NSArray copies and type-checks every element.
    CFArrayRef runs = CTLineGetGlyphRuns(line);
    CFIndex runCount = CFArrayGetCount(runs);
    for (CFIndex index = 0; index < runCount; index++) {
      CTRunRef run = (CTRunRef)CFArrayGetValueAtIndex(runs, index);
      NSDictionary *attributes = (__bridge NSDictionary *)CTRunGetAttributes(run);
      RichTextLinkValue *link = attributes[RichTextAttribute::Link];
      bool underline = attributes[RichTextAttribute::Underline] != nil;
      bool strikethrough = attributes[RichTextAttribute::Strikethrough] != nil;
      if (link == nil && !underline && !strikethrough) continue;

      // Read the run's own origin and width. `CTLineGetOffsetForStringIndex` walks caret
      // offsets over every cluster per call, which profiled at ~20% of a cache miss for
      // Khmer text; these two reads are O(1).
      CGPoint origin = CGPointZero;
      CTRunGetPositions(run, CFRangeMake(0, 1), &origin);
      CGFloat runWidth = (CGFloat)CTRunGetTypographicBounds(run, CFRangeMake(0, 0), NULL, NULL, NULL);
      CGFloat minX = x + origin.x;
      if (runWidth <= 0) continue;

      if (link != nil) {
        hasLinks = true;
        links.push_back(RichTextLinkRect{CGRectMake(minX, top, runWidth, lineHeight), link});
      }

      CTFontRef font = (__bridge CTFontRef)attributes[(id)kCTFontAttributeName];
      if (underline && font != nil) {
        CGFloat thickness = std::max(CTFontGetUnderlineThickness(font), (CGFloat)1);
        CGFloat lineY = baseline - CTFontGetUnderlinePosition(font);
        decorations.push_back(RichTextDecoration{CGRectMake(minX, lineY, runWidth, thickness), link != nil});
      }
      if (strikethrough && font != nil) {
        CGFloat thickness = std::max(CTFontGetUnderlineThickness(font), (CGFloat)1);
        CGFloat lineY = baseline - CTFontGetXHeight(font) / 2 - thickness / 2;
        decorations.push_back(RichTextDecoration{CGRectMake(minX, lineY, runWidth, thickness), link != nil});
      }
    }
    return hasLinks;
  }

  void place(CTLineRef line, CTLineRef _Nullable marker, CGFloat x, CGFloat lineHeight, bool collectGeometry) {
    CGFloat ascent = 0, descent = 0, leading = 0;
    CGFloat lineWidth = (CGFloat)CTLineGetTypographicBounds(line, &ascent, &descent, &leading);
    CGFloat trailingWhitespace = (CGFloat)CTLineGetTrailingWhitespaceWidth(line);
    CGFloat top = y;
    CGFloat baseline = top + (lineHeight - (ascent + descent)) / 2 + ascent;

    const bool hasLinks = collectGeometry && collectRunGeometry(line, x, top, baseline, lineHeight);
    lines.push_back(RichTextPlacedLine{line, CGPointMake(x, baseline), hasLinks});
    if (marker != nil) {
      lines.push_back(RichTextPlacedLine{marker, CGPointMake(0, baseline), false});
    }
    usedWidth = std::max(usedWidth, x + lineWidth - trailingWhitespace);

    y += lineHeight;
    lineCount += 1;
  }
};

// The last visible line when more text follows: the rest of the current hard-break
// segment, truncated to `width` with "…" (or with "…" appended if it already fits).
// Returns an owned (+1) CTLineRef.
CTLineRef truncatedLine(NSAttributedString *text, NSString *string, CTTypesetterRef typesetter, NSInteger start,
                        NSInteger count, double width) {
  NSInteger segmentEnd = start;
  NSInteger length = (NSInteger)string.length;
  while (segmentEnd < length && [string characterAtIndex:(NSUInteger)segmentEnd] != kLineSeparator) segmentEnd++;

  NSMutableAttributedString *segment = [[text attributedSubstringFromRange:NSMakeRange((NSUInteger)start,
                                                                                        (NSUInteger)(segmentEnd - start))]
      mutableCopy];
  NSCharacterSet *whitespace = [NSCharacterSet whitespaceAndNewlineCharacterSet];
  while (segment.length > 0 && [whitespace characterIsMember:[segment.string characterAtIndex:segment.length - 1]]) {
    [segment deleteCharactersInRange:NSMakeRange(segment.length - 1, 1)];
  }

  NSUInteger attrIndex = (NSUInteger)MIN((NSInteger)MAX((NSInteger)segment.length - 1, (NSInteger)0) + start,
                                         (NSInteger)text.length - 1);
  NSMutableDictionary *ellipsisAttributes = [[text attributesAtIndex:attrIndex effectiveRange:NULL] mutableCopy];
  [ellipsisAttributes removeObjectForKey:RichTextAttribute::Link];
  [ellipsisAttributes removeObjectForKey:RichTextAttribute::Underline];
  [ellipsisAttributes removeObjectForKey:RichTextAttribute::Strikethrough];
  ellipsisAttributes[(id)kCTForegroundColorFromContextAttributeName] = @YES;
  NSAttributedString *ellipsis = [[NSAttributedString alloc] initWithString:@"…" attributes:ellipsisAttributes];
  CTLineRef token = CTLineCreateWithAttributedString((CFAttributedStringRef)ellipsis);

  // The whole segment fits on this line: the text continues after a hard break or in
  // the next block, so mark the cut explicitly.
  if (segmentEnd <= start + count) {
    [segment appendAttributedString:ellipsis];
  }

  CTLineRef full = CTLineCreateWithAttributedString((CFAttributedStringRef)segment);
  CTLineRef truncated = CTLineCreateTruncatedLine(full, width, kCTLineTruncationEnd, token);
  CFRelease(token);
  if (truncated != nil) {
    CFRelease(full);
    return truncated;
  }
  return full;
}

} // namespace

std::shared_ptr<RichTextLayout> RichTextLayouter::layout(const RichTextDocument &document, CGFloat width,
                                                          int maxLines) {
  const auto &paragraphs = document.paragraphs();
  if (width <= 0 || paragraphs.empty()) return RichTextLayout::empty();

  Builder builder;
  int limit = maxLines > 0 ? maxLines : INT_MAX;

  for (size_t paragraphIndex = 0; paragraphIndex < paragraphs.size(); paragraphIndex++) {
    if (builder.lineCount >= limit) {
      builder.truncated = true;
      break;
    }
    const RichTextParagraph &paragraph = paragraphs[paragraphIndex];
    if (builder.lineCount > 0) builder.y += paragraph.spacingBefore;

    CTLineRef markerLine = paragraph.prefix != nil
        ? CTLineCreateWithAttributedString((CFAttributedStringRef)paragraph.prefix)
        : nil;
    CGFloat indent = markerLine != nil
        ? (CGFloat)CTLineGetTypographicBounds(markerLine, NULL, NULL, NULL) + kMarkerGap
        : 0;

    double contentWidth = std::max((double)(width - indent), 1.0);

    NSAttributedString *text = paragraph.text;
    NSInteger length = (NSInteger)text.length;
    NSString *string = text.string;
    CFScoped<CTTypesetterRef> typesetter(CTTypesetterCreateWithAttributedString((CFAttributedStringRef)text));
    bool isLastParagraph = paragraphIndex == paragraphs.size() - 1;

    NSInteger start = 0;
    bool isFirstLine = true;
    bool brokeOuter = false;
    while (start < length) {
      CFIndex count = CTTypesetterSuggestLineBreak(typesetter, start, contentWidth);
      if (count <= 0) count = length - start;

      bool hasMore = start + count < length || !isLastParagraph;
      CTLineRef line;
      if (builder.lineCount == limit - 1 && hasMore) {
        line = truncatedLine(text, string, typesetter, start, count, contentWidth);
        builder.truncated = true;
      } else {
        line = CTTypesetterCreateLine(typesetter, CFRangeMake(start, count));
      }

      builder.place(line, isFirstLine ? markerLine : nil, indent, paragraph.lineHeight, paragraph.hasDecorations);
      start += count;
      isFirstLine = false;
      if (builder.truncated) { brokeOuter = true; break; }
    }

    // Browser `<br>` semantics: a trailing break ends the last line but doesn't open another
    // (`<p>a<br></p>` is one line, `<p><br></p>` one empty line) — no extra line here.

    if (brokeOuter) break;
  }

  return std::make_shared<RichTextLayout>(
      std::move(builder.lines), std::move(builder.links), std::move(builder.decorations), width,
      std::min(width, (CGFloat)std::ceil(builder.usedWidth)), (CGFloat)std::ceil(builder.y), builder.lineCount,
      builder.truncated, document.plainText());
}

} // namespace turbohtml
