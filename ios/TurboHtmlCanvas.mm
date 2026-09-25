#import "TurboHtmlCanvas.h"

#import <CoreText/CoreText.h>

#include <memory>

#import "Core/RichTextDocument.h"
#import "Core/RichTextEngine.h"
#import "Core/RichTextLayout.h"

using turbohtml::RichTextEngine;
using turbohtml::RichTextLayout;
using turbohtml::RichTextStyle;

@interface TurboHtmlCanvas () <UIGestureRecognizerDelegate>
@end

@implementation TurboHtmlCanvas {
  NSString *_html;
  RichTextStyle _style;
  NSInteger _numberOfLines;
  std::shared_ptr<RichTextLayout> _layout;
  CGFloat _laidOutWidth;
  UITapGestureRecognizer *_tapRecognizer;
}

// Colors never affect layout, so setting them only redraws.
- (void)setTextColor:(UIColor *)textColor {
  if (textColor == _textColor || [textColor isEqual:_textColor]) return;
  _textColor = textColor;
  [self setNeedsDisplay];
}

- (void)setLinkColor:(UIColor *)linkColor {
  if (linkColor == _linkColor || [linkColor isEqual:_linkColor]) return;
  _linkColor = linkColor;
  [self setNeedsDisplay];
}

- (instancetype)initWithFrame:(CGRect)frame {
  if (self = [super initWithFrame:frame]) {
    _html = @"";
    _style = RichTextStyle{};
    _numberOfLines = 0;
    _layout = RichTextLayout::empty();
    _laidOutWidth = -1;

    self.opaque = NO;
    self.backgroundColor = UIColor.clearColor;
    self.contentMode = UIViewContentModeRedraw;
    self.isAccessibilityElement = YES;
    self.accessibilityTraits = UIAccessibilityTraitStaticText;

    _tapRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTap:)];
    _tapRecognizer.delegate = self;
    [self addGestureRecognizer:_tapRecognizer];
  }
  return self;
}

- (void)setHTML:(NSString *)html
         fontFamily:(NSString *)fontFamily
           fontSize:(double)fontSize
         lineHeight:(double)lineHeight
      numberOfLines:(NSInteger)numberOfLines
 detectPhoneNumbers:(BOOL)detectPhoneNumbers
  headingFontWeight:(NSInteger)headingFontWeight
          fontScale:(double)fontScale {
  RichTextStyle style = RichTextStyle::scaled(fontFamily, fontSize, lineHeight, detectPhoneNumbers,
                                              (int)headingFontWeight, fontScale);
  if ([html isEqualToString:_html] && style == _style && numberOfLines == _numberOfLines) return;

  _html = [html copy];
  _style = style;
  _numberOfLines = numberOfLines;
  [self relayout];
}

/// Fabric recycles component views on iOS (on by default): restore every field to its
/// initial value so nothing from the previous row leaks into the next one. The next
/// `-setHTML:…` then always differs from this state and triggers a fresh layout.
- (void)reset {
  _html = @"";
  _textColor = nil;
  _linkColor = nil;
  _style = RichTextStyle{};
  _numberOfLines = 0;
  _laidOutWidth = -1;
  _layout = RichTextLayout::empty();
  self.accessibilityLabel = nil;
  self.accessibilityCustomActions = nil;
  [self setNeedsDisplay];
}

/// Fabric sets the host's `contentView.frame`; `-layoutSubviews` catches every resize (a
/// `-setBounds:` override would miss frame-driven changes).
- (void)layoutSubviews {
  [super layoutSubviews];
  if (fabs(_laidOutWidth - self.bounds.size.width) > 0.01) [self relayout];
}

- (void)relayout {
  _laidOutWidth = self.bounds.size.width;
  auto next = RichTextEngine::shared().layout(_html, _style, self.bounds.size.width, (int)_numberOfLines);
  if (next == _layout) return;
  _layout = next;
  [self updateAccessibility];
  [self setNeedsDisplay];
}

#pragma mark - Drawing

- (void)drawRect:(CGRect)rect {
  if (_layout->lines().empty()) return;
  CGContextRef context = UIGraphicsGetCurrentContext();
  if (context == NULL) return;

  UITraitCollection *traits = self.traitCollection;
  CGColorRef body = [(_textColor ?: UIColor.labelColor) resolvedColorWithTraitCollection:traits].CGColor;
  CGColorRef link = [(_linkColor ?: UIColor.linkColor) resolvedColorWithTraitCollection:traits].CGColor;

  for (const auto &decoration : _layout->decorations()) {
    CGContextSetFillColorWithColor(context, decoration.isLink ? link : body);
    CGContextFillRect(context, decoration.rect);
  }

  CGContextSaveGState(context);
  CGContextSetTextMatrix(context, CGAffineTransformIdentity);
  CGContextTranslateCTM(context, 0, self.bounds.size.height);
  CGContextScaleCTM(context, 1, -1);
  // Every run uses kCTForegroundColorFromContextAttributeName: the fill color set here.
  for (const auto &placed : _layout->lines()) {
    CGContextSetTextPosition(context, placed.origin.x, self.bounds.size.height - placed.origin.y);
    if (!placed.hasLinks) {
      CGContextSetFillColorWithColor(context, body);
      CTLineDraw(placed.line, context);
      continue;
    }
    CFArrayRef runs = CTLineGetGlyphRuns(placed.line);
    for (CFIndex index = 0, count = CFArrayGetCount(runs); index < count; index++) {
      CTRunRef run = (CTRunRef)CFArrayGetValueAtIndex(runs, index);
      NSDictionary *attributes = (__bridge NSDictionary *)CTRunGetAttributes(run);
      CGContextSetFillColorWithColor(context, attributes[turbohtml::RichTextAttribute::Link] ? link : body);
      CTRunDraw(run, context, CFRangeMake(0, 0));
    }
  }
  CGContextRestoreGState(context);
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
  [super traitCollectionDidChange:previousTraitCollection];
  // Color only lives in `-drawRect:`, so a theme switch never re-parses or re-lays out.
  if ([self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previousTraitCollection]) {
    [self setNeedsDisplay];
  }
}

#pragma mark - Links

- (void)handleTap:(UITapGestureRecognizer *)recognizer {
  RichTextLinkValue *link = _layout->linkAt([recognizer locationInView:self]);
  if (link == nil) return;
  if (self.onLinkPress) self.onLinkPress(link.url, link.isPhone ? @"phone" : @"link");
}

/// Only take the touch when it lands on a link, so taps elsewhere reach the parent
/// `Pressable` (e.g. a list row's own press handler).
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch {
  if (gestureRecognizer != _tapRecognizer) return YES;
  return _layout->linkAt([touch locationInView:self]) != nil;
}

#pragma mark - Accessibility

- (void)updateAccessibility {
  NSString *accessibilityText = _layout->accessibilityText();
  self.accessibilityLabel = accessibilityText.length == 0 ? nil : accessibilityText;

  NSMutableSet<NSString *> *seen = [NSMutableSet set];
  NSMutableArray<UIAccessibilityCustomAction *> *actions = [NSMutableArray array];
  for (const auto &rect : _layout->links()) {
    RichTextLinkValue *link = rect.link;
    if ([seen containsObject:link.url]) continue;
    [seen addObject:link.url];
    NSString *name = link.isPhone ? [NSString stringWithFormat:@"Call %@", [link.url substringFromIndex:4]]
                                  : [NSString stringWithFormat:@"Open %@", link.url];
    __weak __typeof(self) weakSelf = self;
    UIAccessibilityCustomAction *action =
        [[UIAccessibilityCustomAction alloc] initWithName:name
                                        actionHandler:^BOOL(UIAccessibilityCustomAction *_Nonnull customAction) {
                                          __typeof(self) strongSelf = weakSelf;
                                          if (strongSelf.onLinkPress) {
                                            strongSelf.onLinkPress(link.url, link.isPhone ? @"phone" : @"link");
                                          }
                                          return YES;
                                        }];
    [actions addObject:action];
  }
  self.accessibilityCustomActions = actions.count == 0 ? nil : actions;
}

@end
