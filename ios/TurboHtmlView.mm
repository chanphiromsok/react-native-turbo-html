#import "TurboHtmlView.h"

#import <React/RCTUtils.h>
#import <react/renderer/components/TurboHtmlViewSpec/EventEmitters.h>
#import <react/renderer/components/TurboHtmlViewSpec/Props.h>

#import "TurboHtmlCanvas.h"
#import "react/renderer/components/TurboHtmlViewSpec/TurboHtmlViewComponentDescriptor.h"

using namespace facebook::react;

@implementation TurboHtmlView {
  TurboHtmlCanvas *_canvas;
}

+ (ComponentDescriptorProvider)componentDescriptorProvider {
  return concreteComponentDescriptorProvider<TurboHtmlViewComponentDescriptor>();
}

- (instancetype)initWithFrame:(CGRect)frame {
  if (self = [super initWithFrame:frame]) {
    static const auto defaultProps = std::make_shared<const TurboHtmlViewProps>();
    _props = defaultProps;

    _canvas = [[TurboHtmlCanvas alloc] initWithFrame:self.bounds];
    __weak __typeof(self) weakSelf = self;
    _canvas.onLinkPress = ^(NSString *url, NSString *type) {
      [weakSelf emitLinkPress:url type:type];
    };
    self.contentView = _canvas;
  }
  return self;
}

- (void)updateProps:(const Props::Shared &)props oldProps:(const Props::Shared &)oldProps {
  const auto &newProps = *std::static_pointer_cast<const TurboHtmlViewProps>(props);

  [_canvas setHTML:[[NSString alloc] initWithBytes:newProps.html.data()
                                             length:newProps.html.size()
                                           encoding:NSUTF8StringEncoding]
                ?: @""
         fontFamily:[NSString stringWithUTF8String:newProps.fontFamily.c_str()] ?: @"Figtree"
           fontSize:newProps.fontSize
         lineHeight:newProps.lineHeight
      numberOfLines:newProps.numberOfLines
 detectPhoneNumbers:newProps.detectPhoneNumbers
          fontScale:RCTFontSizeMultiplier()];

  [super updateProps:props oldProps:oldProps];
}

- (void)prepareForRecycle {
  [super prepareForRecycle];
  [_canvas reset];
}

- (void)emitLinkPress:(NSString *)url type:(NSString *)type {
  if (!_eventEmitter) {
    return;
  }
  std::static_pointer_cast<const TurboHtmlViewEventEmitter>(_eventEmitter)
      ->onLinkPress({.url = std::string(url.UTF8String ?: ""), .type = std::string(type.UTF8String ?: "")});
}

@end
