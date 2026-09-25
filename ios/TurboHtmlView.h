#import <React/RCTViewComponentView.h>
#import <UIKit/UIKit.h>

#ifndef TurboHtmlViewNativeComponent_h
#define TurboHtmlViewNativeComponent_h

NS_ASSUME_NONNULL_BEGIN

/// Fabric host for `<TurboHtmlView>`. Sizing happens in the hand-written C++ ShadowNode
/// (cpp/react/renderer/components/TurboHtmlViewSpec); this view only forwards props to
/// `TurboHtmlCanvas` and emits `onLinkPress`.
@interface TurboHtmlView : RCTViewComponentView
@end

NS_ASSUME_NONNULL_END

#endif /* TurboHtmlViewNativeComponent_h */
