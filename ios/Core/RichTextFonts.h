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

// CSS-style numeric weight (100–900) → nearest supported weight.
RichTextFontWeight RichTextFontWeightFromNumeric(int weight);

// Resolves `fontFamily` the way RN `<Text>` does, for any app's fonts:
// - empty → the system font;
// - a family name ("Inter", "Kantumruy Pro") or a PostScript name ("Figtree-Regular") →
//   the member of that family whose weight is closest to the requested one, preferring a
//   real italic face when italic is requested;
// - fallback: the `<family>-<Weight>` PostScript convention ("KantumruyPro" →
//   "KantumruyPro-Bold"), then the system font.
// Italics are synthesized (oblique) only when the family has no italic face. Thread-safe
// (locked cache + immutable `CTFont`), so it can run from Yoga's measure pass on any thread.
class RichTextFonts {
 public:
  static CTFontRef font(NSString *family, RichTextFontWeight weight, bool italic, CGFloat size);
};

} // namespace turbohtml
