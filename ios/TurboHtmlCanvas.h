#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Draws a cached RichTextLayout. Hosted by the Fabric `TurboHtmlView` component view.
///
/// Yoga already measured this exact (html, style, width) in the ShadowNode (via
/// `TurboHtmlMeasure`), so the `RichTextEngine` lookup here is a cache hit: no parsing or
/// line breaking on the main thread in the normal path. `-drawRect:` only issues
/// `CTLineDraw` calls and fills decoration rects.
///
/// ObjC++ port of ios/TurboHtmlCanvas.swift.
@interface TurboHtmlCanvas : UIView

@property(nonatomic, copy, nullable) void (^onLinkPress)(NSString *url, NSString *type);

/// Body text color; nil = `UIColor.labelColor`. Dynamic colors (DynamicColorIOS,
/// PlatformColor) are resolved against the view's trait collection at draw time.
@property(nonatomic, strong, nullable) UIColor *textColor;
/// Link and detected-phone color (text + underline); nil = `UIColor.linkColor`.
@property(nonatomic, strong, nullable) UIColor *linkColor;

- (void)setHTML:(NSString *)html
         fontFamily:(NSString *)fontFamily
           fontSize:(double)fontSize
         lineHeight:(double)lineHeight
      numberOfLines:(NSInteger)numberOfLines
 detectPhoneNumbers:(BOOL)detectPhoneNumbers
  headingFontWeight:(NSInteger)headingFontWeight
          fontScale:(double)fontScale;

/// Clears all state for view recycling.
- (void)reset;

@end

NS_ASSUME_NONNULL_END
