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

/// `--color-secondary` (global.css), resolved per trait collection at draw time.
+ (UIColor *)bodyColor {
  static UIColor *color = [UIColor colorWithDynamicProvider:^UIColor *_Nonnull(UITraitCollection *_Nonnull traits) {
    return traits.userInterfaceStyle == UIUserInterfaceStyleDark
        ? [UIColor colorWithRed:0.537 green:0.537 blue:0.537 alpha:1] // oklch(0.6301 0 0)
        : [UIColor colorWithRed:0.490 green:0.490 blue:0.490 alpha:1]; // oklch(0.5897 0 0)
  }];
  return color;
}

- (instancetype)initWithFrame:(CGRect)frame {
  if (self = [super initWithFrame:frame]) {
    _html = @"";
    _style = RichTextStyle{@"Figtree", 14, 20, true};
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
          fontScale:(double)fontScale {
  RichTextStyle style =
      RichTextStyle::scaled(fontFamily, fontSize, lineHeight, detectPhoneNumbers, fontScale);
  if ([html isEqualToString:_html] && style == _style && numberOfLines == _numberOfLines) return;

  _html = [html copy];
  _style = style;
  _numberOfLines = numberOfLines;
  [self relayout];
}

- (void)reset {
  _html = @"";
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

  CGColorRef body = [[TurboHtmlCanvas bodyColor] resolvedColorWithTraitCollection:self.traitCollection].CGColor;
  CGColorRef link = turbohtml::RichTextColors::link();

  for (const auto &decoration : _layout->decorations()) {
    CGContextSetFillColorWithColor(context, decoration.isLink ? link : body);
    CGContextFillRect(context, decoration.rect);
  }

  CGContextSaveGState(context);
  CGContextSetTextMatrix(context, CGAffineTransformIdentity);
  CGContextTranslateCTM(context, 0, self.bounds.size.height);
  CGContextScaleCTM(context, 1, -1);
  CGContextSetFillColorWithColor(context, body); // body runs use kCTForegroundColorFromContextAttributeName
  for (const auto &placed : _layout->lines()) {
    CGContextSetTextPosition(context, placed.origin.x, self.bounds.size.height - placed.origin.y);
    CTLineDraw(placed.line, context);
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
