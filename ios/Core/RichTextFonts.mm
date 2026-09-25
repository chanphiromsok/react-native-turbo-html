#import "RichTextFonts.h"

#include <cmath>
#include <map>
#include <mutex>
#include <string>

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

// Core Text's normalized weight trait for each weight (usWeightClass 400/500/600/700).
CGFloat weightTrait(RichTextFontWeight weight) {
  switch (weight) {
    case RichTextFontWeight::Regular: return 0;
    case RichTextFontWeight::Medium: return 0.23;
    case RichTextFontWeight::SemiBold: return 0.3;
    case RichTextFontWeight::Bold: return 0.4;
  }
  return 0;
}

// All installed faces of `familyName` (app-registered fonts included), or nil.
NSArray *familyMembers(NSString *familyName) {
  if (familyName.length == 0) return nil;
  CTFontDescriptorRef query = CTFontDescriptorCreateWithAttributes(
      (__bridge CFDictionaryRef) @{(id)kCTFontFamilyNameAttribute : familyName});
  NSSet *mandatory = [NSSet setWithObject:(id)kCTFontFamilyNameAttribute];
  NSArray *matches = (__bridge_transfer NSArray *)CTFontDescriptorCreateMatchingFontDescriptors(
      query, (__bridge CFSetRef)mandatory);
  CFRelease(query);
  return matches.count > 0 ? matches : nil;
}

// The family name of an installed font with exactly this PostScript name, or nil.
// (`CTFontCreateWithName` silently substitutes a default font for unknown names.)
NSString *familyOfPostScriptName(NSString *postScriptName) {
  CTFontRef font = CTFontCreateWithName((__bridge CFStringRef)postScriptName, 12, NULL);
  NSString *actual = (__bridge_transfer NSString *)CTFontCopyPostScriptName(font);
  NSString *family = [actual isEqualToString:postScriptName]
      ? (__bridge_transfer NSString *)CTFontCopyFamilyName(font)
      : nil;
  CFRelease(font);
  return family;
}

// Maps whatever the app passed as `fontFamily` to an installed family name, or nil.
NSString *resolveFamilyName(NSString *requested) {
  if (requested.length == 0) return nil;
  if (familyMembers(requested)) return requested;                        // "Inter", "Kantumruy Pro"
  if (NSString *family = familyOfPostScriptName(requested)) return family; // "Figtree-Regular"
  for (NSString *suffix in @[ @"Regular", @"Medium", @"SemiBold", @"Bold" ]) { // "KantumruyPro"
    NSString *name = [NSString stringWithFormat:@"%@-%@", requested, suffix];
    if (NSString *family = familyOfPostScriptName(name)) return family;
  }
  return nil;
}

// Closest-weight face of `familyName`; sets `outIsItalic` to whether the face is italic.
CTFontRef createFromFamily(NSString *familyName, RichTextFontWeight weight, bool italic, CGFloat size,
                           bool *outIsItalic) {
  const CGFloat target = weightTrait(weight);
  CTFontDescriptorRef best = NULL;
  CGFloat bestScore = INFINITY;
  bool bestItalic = false;

  for (id member in familyMembers(familyName)) {
    CTFontDescriptorRef descriptor = (__bridge CTFontDescriptorRef)member;
    NSDictionary *traits =
        (__bridge_transfer NSDictionary *)CTFontDescriptorCopyAttribute(descriptor, kCTFontTraitsAttribute);
    const CGFloat faceWeight = [traits[(id)kCTFontWeightTrait] doubleValue];
    const uint32_t symbolic = [traits[(id)kCTFontSymbolicTrait] unsignedIntValue];
    const bool faceItalic = (symbolic & kCTFontItalicTrait) != 0;
    // Slant mismatch dominates; among equal distances prefer the heavier face for bold
    // requests and the lighter one otherwise (CSS font-matching direction).
    CGFloat score = std::fabs(faceWeight - target) + (faceItalic != italic ? 10 : 0);
    if (faceWeight > target) score += weight == RichTextFontWeight::Regular ? 0.001 : 0;
    if (faceWeight < target) score += weight == RichTextFontWeight::Regular ? 0 : 0.001;
    if (score < bestScore) {
      bestScore = score;
      best = descriptor;
      bestItalic = faceItalic;
    }
  }
  if (!best) return NULL;
  *outIsItalic = bestItalic;
  return CTFontCreateWithFontDescriptor(best, size, NULL);
}

CTFontRef createSystemFont(RichTextFontWeight weight, bool italic, CGFloat size, bool *outIsItalic) {
  CTFontRef system = CTFontCreateUIFontForLanguage(kCTFontUIFontSystem, size, NULL);
  if (!system) system = CTFontCreateWithName(CFSTR("Helvetica"), size, NULL);

  CTFontRef font = system;
  if (weight != RichTextFontWeight::Regular) {
    NSDictionary *traits = @{(id)kCTFontWeightTrait : @(weightTrait(weight))};
    CTFontDescriptorRef base = CTFontCopyFontDescriptor(system);
    CTFontDescriptorRef weighted = CTFontDescriptorCreateCopyWithAttributes(
        base, (__bridge CFDictionaryRef) @{(id)kCTFontTraitsAttribute : traits});
    font = CTFontCreateWithFontDescriptor(weighted, size, NULL);
    CFRelease(weighted);
    CFRelease(base);
    CFRelease(system);
  }
  *outIsItalic = false;
  if (italic) {
    if (CTFontRef italicFont = CTFontCreateCopyWithSymbolicTraits(font, size, NULL, kCTFontItalicTrait,
                                                                   kCTFontItalicTrait)) {
      CFRelease(font);
      font = italicFont;
      *outIsItalic = true;
    }
  }
  return font;
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

RichTextFontWeight RichTextFontWeightFromNumeric(int weight) {
  if (weight >= 650) return RichTextFontWeight::Bold;
  if (weight >= 550) return RichTextFontWeight::SemiBold;
  if (weight >= 450) return RichTextFontWeight::Medium;
  return RichTextFontWeight::Regular;
}

CTFontRef RichTextFonts::font(NSString *family, RichTextFontWeight weight, bool italic, CGFloat size) {
  FontKey key{family.UTF8String ?: "", weight, italic, size};
  {
    std::lock_guard<std::mutex> lock(fontCacheMutex());
    auto it = fontCache().find(key);
    if (it != fontCache().end()) return it->second;
  }

  bool faceIsItalic = false;
  CTFontRef result = NULL;
  if (NSString *familyName = resolveFamilyName(family)) {
    result = createFromFamily(familyName, weight, italic, size, &faceIsItalic);
  }
  if (!result) result = createSystemFont(weight, italic, size, &faceIsItalic);

  if (italic && !faceIsItalic) {
    // The family has no italic face: synthesize a ~12° slant, as RN does.
    CGAffineTransform oblique = CGAffineTransformMake(1, 0, 0.21, 1, 0, 0);
    CTFontRef slanted = CTFontCreateCopyWithAttributes(result, size, &oblique, NULL);
    CFRelease(result);
    result = slanted;
  }

  std::lock_guard<std::mutex> lock(fontCacheMutex());
  // Re-check: another thread may have raced us to fill this key.
  auto it = fontCache().find(key);
  if (it != fontCache().end()) {
    CFRelease(result);
    return it->second;
  }
  if (fontCache().size() > 64) {
    // Attributed strings retain the fonts they use, so dropping the cache's references is safe.
    for (auto &entry : fontCache()) CFRelease(entry.second);
    fontCache().clear();
  }
  fontCache()[key] = result;
  return result;
}

} // namespace turbohtml
