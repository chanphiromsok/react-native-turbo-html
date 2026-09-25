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

- (void)setHTML:(NSString *)html
         fontFamily:(NSString *)fontFamily
           fontSize:(double)fontSize
         lineHeight:(double)lineHeight
      numberOfLines:(NSInteger)numberOfLines
 detectPhoneNumbers:(BOOL)detectPhoneNumbers
          fontScale:(double)fontScale;

/// Clears all state for view recycling.
- (void)reset;

@end

NS_ASSUME_NONNULL_END
