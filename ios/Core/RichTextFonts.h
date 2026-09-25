#pragma once

#import <CoreGraphics/CoreGraphics.h>
#import <CoreText/CoreText.h>
#import <Foundation/Foundation.h>

// ObjC++ port of ios/Core/RichTextFonts.swift.
namespace turbohtml {

enum class RichTextFontWeight {
  Regular,
  Medium,
  SemiBold,
  Bold,
};

NSString *RichTextFontWeightSuffix(RichTextFontWeight weight);

// Resolves the host app's bundled fonts (`Figtree-*`, `KantumruyPro-*`, registered via
// Info.plist) as `CTFont`s. Thread-safe (locked cache + immutable `CTFont`), so it can run
// from Yoga's measure pass on any thread.
class RichTextFonts {
 public:
  static CTFontRef font(NSString *family, RichTextFontWeight weight, bool italic, CGFloat size);
};

} // namespace turbohtml
