#import "RichTextFonts.h"

#include <map>
#include <mutex>
#include <string>
#include <vector>

namespace turbohtml {

namespace {

struct FontKey {
  std::string family;
  RichTextFontWeight weight;
  bool italic;
  CGFloat size;

  bool operator<(const FontKey &other) const {
    if (family != other.family) return family < other.family;
    if (weight != other.weight) return weight < other.weight;
    if (italic != other.italic) return italic < other.italic;
    return size < other.size;
  }
};

std::mutex &fontCacheMutex() {
  static std::mutex m;
  return m;
}

std::map<FontKey, CTFontRef> &fontCache() {
  static std::map<FontKey, CTFontRef> cache;
  return cache;
}

// Some families lack weights (e.g. KantumruyPro has no ExtraBold), so try nearby ones.
const std::vector<RichTextFontWeight> &fallbackChain(RichTextFontWeight weight) {
  static const std::vector<RichTextFontWeight> regular = {RichTextFontWeight::Regular};
  static const std::vector<RichTextFontWeight> medium = {RichTextFontWeight::Medium, RichTextFontWeight::Regular};
  static const std::vector<RichTextFontWeight> semibold = {
      RichTextFontWeight::SemiBold, RichTextFontWeight::Medium, RichTextFontWeight::Bold, RichTextFontWeight::Regular};
  static const std::vector<RichTextFontWeight> bold = {
      RichTextFontWeight::Bold, RichTextFontWeight::SemiBold, RichTextFontWeight::Regular};
  switch (weight) {
    case RichTextFontWeight::Regular: return regular;
    case RichTextFontWeight::Medium: return medium;
    case RichTextFontWeight::SemiBold: return semibold;
    case RichTextFontWeight::Bold: return bold;
  }
  return regular;
}

CGFloat systemWeight(RichTextFontWeight weight) {
  switch (weight) {
    case RichTextFontWeight::Regular: return 0;
    case RichTextFontWeight::Medium: return 0.23;
    case RichTextFontWeight::SemiBold: return 0.3;
    case RichTextFontWeight::Bold: return 0.4;
  }
  return 0;
}

CTFontRef createUprightFont(NSString *family, RichTextFontWeight weight, CGFloat size) {
  for (RichTextFontWeight candidate : fallbackChain(weight)) {
    NSString *name = [NSString stringWithFormat:@"%@-%@", family, RichTextFontWeightSuffix(candidate)];
    CTFontRef font = CTFontCreateWithName((__bridge CFStringRef)name, size, NULL);
    // CTFontCreateWithName silently substitutes a default font for unknown names.
    NSString *postScriptName = (__bridge_transfer NSString *)CTFontCopyPostScriptName(font);
    if ([postScriptName isEqualToString:name]) {
      return font;
    }
    CFRelease(font);
  }

  CTFontRef system = CTFontCreateUIFontForLanguage(kCTFontUIFontSystem, size, NULL);
  if (!system) {
    system = CTFontCreateWithName(CFSTR("Helvetica"), size, NULL);
  }
  if (weight == RichTextFontWeight::Regular) {
    return system;
  }

  CGFloat weightValue = systemWeight(weight);
  NSDictionary *traits = @{(id)kCTFontWeightTrait : @(weightValue)};
  CTFontDescriptorRef baseDescriptor = CTFontCopyFontDescriptor(system);
  CTFontDescriptorRef descriptor = CTFontDescriptorCreateCopyWithAttributes(
      baseDescriptor, (__bridge CFDictionaryRef) @{(id)kCTFontTraitsAttribute : traits});
  CFRelease(baseDescriptor);
  CFRelease(system);
  CTFontRef result = CTFontCreateWithFontDescriptor(descriptor, size, NULL);
  CFRelease(descriptor);
  return result;
}

} // namespace

NSString *RichTextFontWeightSuffix(RichTextFontWeight weight) {
  switch (weight) {
    case RichTextFontWeight::Regular: return @"Regular";
    case RichTextFontWeight::Medium: return @"Medium";
    case RichTextFontWeight::SemiBold: return @"SemiBold";
    case RichTextFontWeight::Bold: return @"Bold";
  }
  return @"Regular";
}

CTFontRef RichTextFonts::font(NSString *family, RichTextFontWeight weight, bool italic, CGFloat size) {
  FontKey key{family.UTF8String ?: "", weight, italic, size};

  {
    std::lock_guard<std::mutex> lock(fontCacheMutex());
    auto it = fontCache().find(key);
    if (it != fontCache().end()) return it->second;
  }

  CTFontRef upright = createUprightFont(family, weight, size);
  CTFontRef result = upright;
  if (italic) {
    // Figtree and KantumruyPro ship no italic files, so synthesize a ~12° slant.
    CGAffineTransform oblique = CGAffineTransformMake(1, 0, 0.21, 1, 0, 0);
    CTFontRef italicFont = CTFontCreateCopyWithAttributes(upright, size, &oblique, NULL);
    CFRelease(upright);
    result = italicFont;
  }

  std::lock_guard<std::mutex> lock(fontCacheMutex());
  // Re-check: another thread may have raced us to fill this key.
  auto it = fontCache().find(key);
  if (it != fontCache().end()) {
    CFRelease(result);
    return it->second;
  }
  if (fontCache().size() > 64) {
    for (auto &entry : fontCache()) CFRelease(entry.second);
    fontCache().clear();
  }
  fontCache()[key] = result;
  return result;
}

} // namespace turbohtml
