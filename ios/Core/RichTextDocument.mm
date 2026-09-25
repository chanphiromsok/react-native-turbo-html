#import "RichTextDocument.h"

#import "HTMLScanner.h"

#include <unordered_map>
#include <vector>

namespace turbohtml {

NSString *const RichTextAttribute::Link = @"TurboHtmlLink";
NSString *const RichTextAttribute::Underline = @"TurboHtmlUnderline";
NSString *const RichTextAttribute::Strikethrough = @"TurboHtmlStrikethrough";

CGColorRef RichTextColors::link() {
  static CGColorRef color = CGColorCreateGenericRGB(0.016, 0.671, 0.322, 1);
  return color;
}

RichTextStyle RichTextStyle::scaled(NSString *fontFamily, double fontSize, double lineHeight,
                                    bool detectPhoneNumbers, double fontScale) {
  double scale = fontScale > 0 ? fontScale : 1;
  double size = fontSize > 0 ? fontSize : 14;
  double height = lineHeight > 0 ? lineHeight : 20;
  RichTextStyle style;
  style.fontFamily = fontFamily.length > 0 ? fontFamily : @"Figtree";
  style.fontSize = (CGFloat)(size * scale);
  style.lineHeight = (CGFloat)(height * scale);
  style.detectPhoneNumbers = detectPhoneNumbers;
  return style;
}

} // namespace turbohtml

@implementation RichTextLinkValue
- (instancetype)initWithUrl:(NSString *)url isPhone:(BOOL)isPhone {
  if (self = [super init]) {
    _url = url;
    _isPhone = isPhone;
  }
  return self;
}
@end

namespace turbohtml {

namespace {

constexpr CGFloat kBlockGap = 4;
NSString *const kLineBreak = @" ";

enum class FrameKind { Generic, List, Paragraph, Inline, Ignored };

struct InlineStyle {
  RichTextFontWeight weight = RichTextFontWeight::Regular;
  bool italic = false;
  bool underline = false;
  bool strikethrough = false;
  RichTextLinkValue *link = nil;

  // Cache key for styles without a link (links carry a per-URL value). -1 means "no key".
  int attributesKey() const {
    if (link != nil) return -1;
    return (int)weight * 16 + (italic ? 1 : 0) + (underline ? 2 : 0) + (strikethrough ? 4 : 0);
  }
};

struct Frame {
  FrameKind kind;
  HTMLTag tag;
  InlineStyle style;
  bool ordered = false;
  int itemCount = 0;
};

struct Run {
  NSRange range;
  NSDictionary *attributes;
};

bool hasVisibleContent(NSString *s) {
  NSUInteger len = s.length;
  for (NSUInteger i = 0; i < len; i++) {
    unichar c = [s characterAtIndex:i];
    if (!(c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D || c == 0x0C)) return true;
  }
  return false;
}

// Raw newlines in HTML text render as line breaks in RenderHtml (RN `<Text>` keeps them).
NSString *normalizeNewlines(NSString *s) {
  if ([s rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"\r\n"]].location == NSNotFound) {
    return s;
  }
  NSString *result = [s stringByReplacingOccurrencesOfString:@"\r\n" withString:kLineBreak];
  result = [result stringByReplacingOccurrencesOfString:@"\r" withString:kLineBreak];
  result = [result stringByReplacingOccurrencesOfString:@"\n" withString:kLineBreak];
  return result;
}

// Builds a `RichTextDocument` from HTML; implements `HTMLEventSink` to receive the
// scanner's events. Mirrors `RichTextDocumentBuilder` in ios/Core/RichTextDocument.swift.
class DocumentBuilderImpl final : public HTMLEventSink {
 public:
  explicit DocumentBuilderImpl(const RichTextStyle &style) : style_(style), plainText_([NSMutableString new]) {}

  void openTag(const HTMLTag &tag, NSString *_Nullable href, bool selfClosing) override {
    if (!frames_.empty() && frames_.back().kind == FrameKind::Ignored) {
      if (!selfClosing) frames_.push_back(Frame{FrameKind::Ignored, tag});
      return;
    }

    if (current_ != nil) closeParagraphIfImplied(tag);

    if (current_ != nil) {
      openInline(tag, href, selfClosing);
      return;
    }

    if (frames_.empty()) beginTopLevelChild();

    if (!frames_.empty() && frames_.back().kind == FrameKind::List) {
      if (tag.kind == HTMLTagKind::Li) {
        frames_.back().itemCount += 1;
        int number = frames_.back().itemCount;
        bool ordered = frames_.back().ordered;
        if (number > 1) pendingGap_ = kBlockGap;
        NSString *marker = ordered ? [NSString stringWithFormat:@"%d.", number] : @"•";
        beginParagraph(marker);
        frames_.push_back(Frame{FrameKind::Paragraph, tag, InlineStyle()});
      } else if (!selfClosing) {
        // Non-`li` children of a list are dropped, like RenderHtml's `li` filter.
        frames_.push_back(Frame{FrameKind::Ignored, tag});
      }
      return;
    }

    switch (tag.kind) {
      case HTMLTagKind::Head:
      case HTMLTagKind::Script:
      case HTMLTagKind::Style:
      case HTMLTagKind::Meta:
      case HTMLTagKind::Link:
        if (!selfClosing) frames_.push_back(Frame{FrameKind::Ignored, tag});
        break;
      case HTMLTagKind::P:
      case HTMLTagKind::Li:
      case HTMLTagKind::H1:
      case HTMLTagKind::H2:
      case HTMLTagKind::H3:
      case HTMLTagKind::H4:
      case HTMLTagKind::H5:
      case HTMLTagKind::H6: {
        beginParagraph(nil);
        InlineStyle paragraphStyle;
        paragraphStyle.weight = headingWeight(tag);
        frames_.push_back(Frame{FrameKind::Paragraph, tag, paragraphStyle});
        break;
      }
      case HTMLTagKind::Ul:
      case HTMLTagKind::Ol: {
        Frame f{FrameKind::List, tag};
        f.ordered = tag.kind == HTMLTagKind::Ol;
        frames_.push_back(f);
        break;
      }
      default:
        if (!selfClosing) frames_.push_back(Frame{FrameKind::Generic, tag});
        break;
    }
  }

  void closeTag(const HTMLTag &tag) override {
    for (size_t k = frames_.size(); k > 0; k--) {
      if (frames_[k - 1].tag == tag) {
        pop(k - 1);
        return;
      }
    }
  }

  void text(NSString *text) override {
    if (frames_.empty()) {
      appendBlockText(text);
      return;
    }
    const Frame &top = frames_.back();
    switch (top.kind) {
      case FrameKind::Ignored:
      case FrameKind::List:
        return;
      case FrameKind::Paragraph:
      case FrameKind::Inline:
        appendRun(text, top.style, style_.detectPhoneNumbers && top.style.link == nil);
        return;
      case FrameKind::Generic:
        appendBlockText(text);
        return;
    }
  }

  void closeAll() {
    pop(0);
    finishParagraph();
  }

  std::vector<RichTextParagraph> &paragraphs() { return paragraphs_; }
  NSString *plainText() const { return plainText_; }

 private:
  void beginTopLevelChild() { pendingGap_ = paragraphs_.empty() ? 0 : kBlockGap; }

  void beginParagraph(NSString *_Nullable marker) {
    finishParagraph();
    current_ = [NSMutableString new];
    currentRuns_.clear();
    currentHasDecorations_ = false;
    currentSpacing_ = pendingGap_;
    if (marker != nil) {
      NSDictionary *attrs = attributes(InlineStyle());
      currentPrefix_ = [[NSAttributedString alloc] initWithString:marker attributes:attrs];
    } else {
      currentPrefix_ = nil;
    }
  }

  void finishParagraph() {
    if (current_ == nil) return;
    NSMutableString *text = current_;
    current_ = nil;
    if (text.length == 0) return;

    CFMutableAttributedStringRef attributed = CFAttributedStringCreateMutable(kCFAllocatorDefault, 0);
    CFAttributedStringReplaceString(attributed, CFRangeMake(0, 0), (__bridge CFStringRef)text);
    CFAttributedStringBeginEditing(attributed);
    for (const auto &run : currentRuns_) {
      CFAttributedStringSetAttributes(attributed, CFRangeMake(run.range.location, run.range.length),
                                       (__bridge CFDictionaryRef)run.attributes, true);
    }
    CFAttributedStringEndEditing(attributed);
    NSAttributedString *finalText = (__bridge_transfer NSAttributedString *)attributed;

    paragraphs_.push_back(RichTextParagraph{finalText, currentPrefix_, style_.lineHeight, currentSpacing_,
                                             currentHasDecorations_});
    pendingGap_ = 0;

    if (plainText_.length > 0) [plainText_ appendString:@"\n"];
    if (currentPrefix_ != nil) {
      [plainText_ appendString:currentPrefix_.string];
      [plainText_ appendString:@" "];
    }
    if ([text rangeOfString:kLineBreak].location != NSNotFound) {
      [plainText_ appendString:[text stringByReplacingOccurrencesOfString:kLineBreak withString:@"\n"]];
    } else {
      [plainText_ appendString:text];
    }
  }

  void appendBlockText(NSString *raw) {
    if (!hasVisibleContent(raw)) return;
    if (frames_.empty()) beginTopLevelChild();
    beginParagraph(nil);
    appendRun(raw, InlineStyle(), false);
    finishParagraph();
  }

  // htmlparser2 (behind RenderHtml) implicitly closes an open `<p>` when a block starts,
  // and an open `<li>` when the next `<li>` starts — but only when that element is the
  // innermost open one (so `<li>a<ul><li>b` nests instead of closing the outer item).
  void closeParagraphIfImplied(const HTMLTag &tag) {
    if (frames_.empty() || frames_.back().kind != FrameKind::Paragraph) return;
    HTMLTagKind open = frames_.back().tag.kind;
    bool closes = false;
    if (open == HTMLTagKind::P) {
      switch (tag.kind) {
        case HTMLTagKind::P:
        case HTMLTagKind::Div:
        case HTMLTagKind::Ul:
        case HTMLTagKind::Ol:
        case HTMLTagKind::H1:
        case HTMLTagKind::H2:
        case HTMLTagKind::H3:
        case HTMLTagKind::H4:
        case HTMLTagKind::H5:
        case HTMLTagKind::H6:
          closes = true;
          break;
        default:
          break;
      }
    } else if (open == HTMLTagKind::Li && tag.kind == HTMLTagKind::Li) {
      closes = true;
    }
    if (closes) pop(frames_.size() - 1);
  }

  void pop(size_t index) {
    if (index >= frames_.size()) return;
    bool poppedParagraph = false;
    for (size_t k = index; k < frames_.size(); k++) {
      if (frames_[k].kind == FrameKind::Paragraph) { poppedParagraph = true; break; }
    }
    frames_.erase(frames_.begin() + (long)index, frames_.end());
    if (poppedParagraph) finishParagraph();
  }

  RichTextFontWeight headingWeight(const HTMLTag &tag) const {
    switch (tag.kind) {
      case HTMLTagKind::H1:
      case HTMLTagKind::H2:
        // RenderHtml: `font-bold`, which fontMapper maps to semibold for Khmer.
        return [style_.fontFamily isEqualToString:@"KantumruyPro"] ? RichTextFontWeight::SemiBold
                                                                    : RichTextFontWeight::Bold;
      case HTMLTagKind::H3:
      case HTMLTagKind::H4:
        return RichTextFontWeight::SemiBold;
      default:
        return RichTextFontWeight::Regular;
    }
  }

  void openInline(const HTMLTag &tag, NSString *_Nullable href, bool selfClosing) {
    switch (tag.kind) {
      case HTMLTagKind::Br: {
        InlineStyle style = frames_.empty() ? InlineStyle() : frames_.back().style;
        append(kLineBreak, style);
        return;
      }
      case HTMLTagKind::Head:
      case HTMLTagKind::Script:
      case HTMLTagKind::Style:
      case HTMLTagKind::Meta:
      case HTMLTagKind::Link:
        if (!selfClosing) frames_.push_back(Frame{FrameKind::Ignored, tag});
        return;
      default:
        break;
    }
    if (selfClosing) return;

    InlineStyle next = frames_.empty() ? InlineStyle() : frames_.back().style;
    switch (tag.kind) {
      case HTMLTagKind::B:
      case HTMLTagKind::Strong:
        next.weight = RichTextFontWeight::Bold;
        break;
      case HTMLTagKind::I:
      case HTMLTagKind::Em:
        next.italic = true;
        break;
      case HTMLTagKind::U:
        next.underline = true;
        break;
      case HTMLTagKind::S:
      case HTMLTagKind::Del:
        next.strikethrough = true;
        break;
      case HTMLTagKind::A: {
        NSString *url = href != nil ? RichTextDocumentBuilder::linkURL(href) : nil;
        if (url != nil) next.link = [[RichTextLinkValue alloc] initWithUrl:url isPhone:NO];
        break;
      }
      default:
        break;
    }
    frames_.push_back(Frame{FrameKind::Inline, tag, next});
  }

  void appendRun(NSString *raw, const InlineStyle &style, bool detectPhones) {
    if (current_ == nil || raw.length == 0) return;

    if (!detectPhones) {
      append(normalizeNewlines(raw), style);
      return;
    }

    NSUInteger cursor = 0;
    for (const NSRange &range : RichTextPhoneDetector::matches(raw)) {
      if (range.location > cursor) {
        append(normalizeNewlines([raw substringWithRange:NSMakeRange(cursor, range.location - cursor)]), style);
      }
      NSString *number = [raw substringWithRange:range];
      InlineStyle phoneStyle = style;
      NSString *tel = [@"tel:" stringByAppendingString:[number stringByReplacingOccurrencesOfString:@" "
                                                                                           withString:@""]];
      phoneStyle.link = [[RichTextLinkValue alloc] initWithUrl:tel isPhone:YES];
      append(number, phoneStyle);
      cursor = range.location + range.length;
    }
    if (cursor < raw.length) {
      append(normalizeNewlines([raw substringFromIndex:cursor]), style);
    }
  }

  // Appends text to the open block and records its attribute run, merging with the
  // previous run when the style is the same cached dictionary.
  void append(NSString *string, const InlineStyle &style) {
    if (current_ == nil || string.length == 0) return;
    NSDictionary *attrs = attributes(style);
    NSUInteger location = current_.length;
    [current_ appendString:string];
    NSUInteger length = current_.length - location;
    if (length == 0) return;

    if (!currentRuns_.empty() && currentRuns_.back().attributes == attrs &&
        NSMaxRange(currentRuns_.back().range) == location) {
      currentRuns_.back().range.length += length;
    } else {
      currentRuns_.push_back(Run{NSMakeRange(location, length), attrs});
    }
    if (style.link != nil || style.underline || style.strikethrough) currentHasDecorations_ = true;
  }

  NSDictionary *attributes(const InlineStyle &style) {
    int key = style.attributesKey();
    if (key < 0) return makeAttributes(style);
    auto it = attributesCache_.find(key);
    if (it != attributesCache_.end()) return it->second;
    NSDictionary *made = makeAttributes(style);
    attributesCache_[key] = made;
    return made;
  }

  NSDictionary *makeAttributes(const InlineStyle &style) const {
    NSMutableDictionary *attrs = [NSMutableDictionary dictionaryWithCapacity:4];
    attrs[(id)kCTFontAttributeName] =
        (__bridge id)RichTextFonts::font(style_.fontFamily, style.weight, style.italic, style_.fontSize);
    if (style.link != nil) {
      attrs[(id)kCTForegroundColorAttributeName] = (__bridge id)RichTextColors::link();
      attrs[RichTextAttribute::Link] = style.link;
      attrs[RichTextAttribute::Underline] = @YES;
    } else {
      attrs[(id)kCTForegroundColorFromContextAttributeName] = @YES;
      if (style.underline) attrs[RichTextAttribute::Underline] = @YES;
    }
    if (style.strikethrough) attrs[RichTextAttribute::Strikethrough] = @YES;
    return [attrs copy];
  }

  RichTextStyle style_;
  std::vector<Frame> frames_;
  std::vector<RichTextParagraph> paragraphs_;
  NSMutableString *plainText_;

  std::unordered_map<int, NSDictionary *> attributesCache_;
  NSMutableString *_Nullable current_ = nil;
  std::vector<Run> currentRuns_;
  bool currentHasDecorations_ = false;
  NSAttributedString *_Nullable currentPrefix_ = nil;
  CGFloat currentSpacing_ = 0;
  CGFloat pendingGap_ = 0;
};

} // namespace

std::shared_ptr<RichTextDocument> RichTextDocumentBuilder::build(const char *html, size_t htmlLength,
                                                                  const RichTextStyle &style) {
  DocumentBuilderImpl builder(style);
  HTMLScanner::scan(html, htmlLength, builder);
  builder.closeAll();
  return std::make_shared<RichTextDocument>(std::move(builder.paragraphs()), builder.plainText());
}

NSString *RichTextDocumentBuilder::linkURL(NSString *href) {
  NSString *candidate = [href stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  if (candidate.length == 0) return nil;
  if ([[candidate lowercaseString] hasPrefix:@"www."]) {
    candidate = [@"https://" stringByAppendingString:candidate];
  }
  NSURL *url = [NSURL URLWithString:candidate];
  if (url == nil) {
    NSString *encoded = [candidate stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet
                                                                                           URLQueryAllowedCharacterSet]];
    url = encoded != nil ? [NSURL URLWithString:encoded] : nil;
  }
  if (url == nil) return nil;
  NSString *scheme = [url.scheme lowercaseString];
  static NSSet<NSString *> *allowed = [NSSet setWithObjects:@"http", @"https", @"mailto", @"tel", nil];
  if (scheme == nil || ![allowed containsObject:scheme]) return nil;
  return url.absoluteString;
}

std::vector<NSRange> RichTextPhoneDetector::matches(NSString *text) {
  std::vector<NSRange> result;

  // Cheap pre-check: most runs have fewer than 8 digits, so skip the regex entirely.
  NSUInteger digitCount = 0;
  NSUInteger length = text.length;
  for (NSUInteger i = 0; i < length; i++) {
    unichar c = [text characterAtIndex:i];
    if (c >= '0' && c <= '9') {
      digitCount += 1;
      if (digitCount >= 8) break;
    }
  }
  if (digitCount < 8) return result;

  static NSRegularExpression *candidatePattern =
      [NSRegularExpression regularExpressionWithPattern:@"\\+?\\d[\\d \\-]{6,}\\d" options:0 error:nil];
  static NSRegularExpression *dateShapePattern = [NSRegularExpression
      regularExpressionWithPattern:@"^(\\d{4}-\\d{1,2}-\\d{1,2}|\\d{1,2}-\\d{1,2}-\\d{4})$"
                           options:0
                             error:nil];

  NSArray<NSTextCheckingResult *> *found =
      [candidatePattern matchesInString:text options:0 range:NSMakeRange(0, length)];
  for (NSTextCheckingResult *match in found) {
    NSRange range = match.range;
    NSString *value = [text substringWithRange:range];
    NSUInteger digits = 0;
    for (NSUInteger i = 0; i < value.length; i++) {
      unichar c = [value characterAtIndex:i];
      if (c >= '0' && c <= '9') digits += 1;
    }
    if (digits < 8 || digits > 15) continue;
    NSRange valueWhole = NSMakeRange(0, value.length);
    if ([dateShapePattern firstMatchInString:value options:0 range:valueWhole] != nil) continue;
    result.push_back(range);
  }
  return result;
}

} // namespace turbohtml
