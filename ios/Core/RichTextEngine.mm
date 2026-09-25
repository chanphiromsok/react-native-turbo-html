#import "RichTextEngine.h"

#include <cmath>
#include <cstring>
#include <string>
#include <utility>
#include <vector>

using turbohtml::RichTextDocument;
using turbohtml::RichTextLayout;
using turbohtml::RichTextLayouter;
using turbohtml::RichTextStyle;

namespace {

// Hashes UTF-8 bytes 8 at a time: much cheaper than hashing through `-[NSString hash]` for
// long strings. Only picks a bucket; equality is still checked with a full byte compare.
uint64_t RawByteHash(const char *raw, size_t byteLength) {
  uint64_t hash = 0xCBF29CE484222325ULL ^ (uint64_t)byteLength;
  size_t offset = 0;
  while (offset + 8 <= byteLength) {
    uint64_t chunk;
    memcpy(&chunk, raw + offset, 8);
    hash = (hash ^ chunk) * 0x00000100000001B3ULL;
    hash ^= hash >> 29;
    offset += 8;
  }
  while (offset < byteLength) {
    hash = (hash ^ (uint64_t)(uint8_t)raw[offset]) * 0x00000100000001B3ULL;
    offset += 1;
  }
  return hash ^ (hash >> 32);
}

NSUInteger CombineHash(NSUInteger seed, NSUInteger value) {
  return seed ^ (value + 0x9e3779b9u + (seed << 6) + (seed >> 2));
}

NSUInteger HashStyle(const RichTextStyle &style) {
  NSUInteger h = [style.fontFamily hash];
  h = CombineHash(h, (NSUInteger)llround(style.fontSize * 1000));
  h = CombineHash(h, (NSUInteger)llround(style.lineHeight * 1000));
  h = CombineHash(h, style.detectPhoneNumbers ? 1u : 0u);
  return h;
}

// Best-effort zero-copy view of an NSString's UTF-8 bytes (used only by the `NSString *`
// overload, i.e. the component view's draw path, not the hot measure path). Falls back to
// a copy when the string isn't already backed by a UTF-8/ASCII-compatible buffer (true for
// most non-Latin scripts, since Foundation commonly stores those as UTF-16).
struct Utf8View {
  const char *data;
  size_t length;
  std::string owned; // populated only when a copy was necessary
};

Utf8View MakeUtf8View(NSString *s) {
  Utf8View view;
  const char *fast = CFStringGetCStringPtr((__bridge CFStringRef)s, kCFStringEncodingUTF8);
  if (fast != NULL) {
    view.data = fast;
    view.length = strlen(fast);
    return view;
  }
  NSUInteger len = [s lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
  view.owned.resize(len);
  if (len > 0) {
    [s getBytes:(void *)view.owned.data()
              maxLength:len
             usedLength:NULL
               encoding:NSUTF8StringEncoding
                options:0
                  range:NSMakeRange(0, s.length)
         remainingRange:NULL];
  }
  view.data = view.owned.data();
  view.length = len;
  return view;
}

} // namespace

// Cache key: html bytes + style. Two flavors:
//  - a *borrowed* key (no copy) for a lookup — safe because it never outlives the call that
//    constructed it, and NSCache's `-objectForKey:` only reads the key during that call;
//  - an *owned* key (copies the bytes once) for actually inserting into the cache.
// This keeps a cache *hit* on the measure path (`TurboHtmlMeasure`, which already holds the
// ShadowNode's raw `std::string` bytes) completely allocation-free.
@interface TurboHtmlDocumentKey : NSObject {
 @public
  turbohtml::RichTextStyle style;
}
- (instancetype)initWithBytes:(const char *)bytes length:(size_t)length style:(const turbohtml::RichTextStyle &)style
                          copy:(BOOL)copy;
@end

@implementation TurboHtmlDocumentKey {
  const char *_bytes; // borrowed or pointing into `_owned`
  size_t _length;
  std::string _owned;
  NSUInteger _precomputedHash;
}

- (instancetype)initWithBytes:(const char *)bytes
                        length:(size_t)length
                         style:(const turbohtml::RichTextStyle &)styleValue
                          copy:(BOOL)copy {
  if (self = [super init]) {
    style = styleValue;
    if (copy) {
      _owned.assign(bytes, length);
      _bytes = _owned.data();
      _length = _owned.size();
    } else {
      _bytes = bytes;
      _length = length;
    }
    _precomputedHash = CombineHash((NSUInteger)RawByteHash(_bytes, _length), HashStyle(styleValue));
  }
  return self;
}

- (NSUInteger)hash {
  return _precomputedHash;
}

- (BOOL)isEqual:(id)object {
  if (self == object) return YES;
  if (![object isKindOfClass:[TurboHtmlDocumentKey class]]) return NO;
  TurboHtmlDocumentKey *other = (TurboHtmlDocumentKey *)object;
  if (_precomputedHash != other->_precomputedHash) return NO;
  if (style != other->style) return NO;
  if (_length != other->_length) return NO;
  return _length == 0 || memcmp(_bytes, other->_bytes, _length) == 0;
}

@end

// A phone feed renders at one width; a second covers rotation or split view.
static const int kMaxLayouts = 2;

@interface TurboHtmlCacheEntry : NSObject
- (instancetype)initWithDocument:(std::shared_ptr<RichTextDocument>)document;
- (const std::shared_ptr<RichTextDocument> &)document;
- (std::shared_ptr<RichTextLayout>)layoutForWidth:(CGFloat)width maxLines:(int)maxLines;
@end

@implementation TurboHtmlCacheEntry {
  std::shared_ptr<RichTextDocument> _document;
  std::vector<std::pair<std::pair<int, int>, std::shared_ptr<RichTextLayout>>> _layouts; // (widthBucket, maxLines)
  NSLock *_lock;
}

- (instancetype)initWithDocument:(std::shared_ptr<RichTextDocument>)document {
  if (self = [super init]) {
    _document = std::move(document);
    _lock = [NSLock new];
  }
  return self;
}

- (const std::shared_ptr<RichTextDocument> &)document {
  return _document;
}

- (std::shared_ptr<RichTextLayout>)layoutForWidth:(CGFloat)width maxLines:(int)maxLines {
  // Quarter-point buckets: Yoga's width and the view's bounds agree to well under that.
  int widthBucket = (int)llround(width * 4);

  [_lock lock];
  for (const auto &entry : _layouts) {
    if (entry.first.first == widthBucket && entry.first.second == maxLines) {
      auto cached = entry.second;
      [_lock unlock];
      return cached;
    }
  }
  [_lock unlock];

  auto computed = RichTextLayouter::layout(*_document, width, maxLines);

  [_lock lock];
  if ((int)_layouts.size() >= kMaxLayouts) _layouts.clear();
  _layouts.push_back({{widthBucket, maxLines}, computed});
  [_lock unlock];
  return computed;
}

@end

namespace turbohtml {

namespace {

// Approximate bytes an entry holds: the attributed text plus up to `kMaxLayouts` laid-out
// copies (glyphs, advances, positions, string indices ≈ 50 B per UTF-16 unit).
NSUInteger estimatedCost(const std::shared_ptr<RichTextDocument> &document) {
  NSUInteger units = 0;
  for (const auto &paragraph : document->paragraphs()) units += paragraph.text.length;
  return units * (16 + 50 * kMaxLayouts);
}

NSCache<TurboHtmlDocumentKey *, TurboHtmlCacheEntry *> *DocumentCache() {
  // Sized for a feed: ~100 descriptions is ~10 screens of rows, enough for scroll-back
  // hits, while `NSCache` still drops entries under memory pressure.
  static NSCache<TurboHtmlDocumentKey *, TurboHtmlCacheEntry *> *cache = ^{
    NSCache<TurboHtmlDocumentKey *, TurboHtmlCacheEntry *> *c = [NSCache new];
    c.countLimit = 100;
    c.totalCostLimit = 8 * 1024 * 1024;
    return c;
  }();
  return cache;
}

} // namespace

RichTextEngine::RichTextEngine() {}

RichTextEngine &RichTextEngine::shared() {
  static RichTextEngine instance;
  return instance;
}

std::shared_ptr<RichTextLayout> RichTextEngine::layout(const char *html, size_t htmlLength, const RichTextStyle &style,
                                                        CGFloat width, int maxLines) {
  if (htmlLength == 0 || width <= 0) return RichTextLayout::empty();

  // Borrowed key: no allocation. Safe because `html`/`htmlLength` (the caller's live
  // buffer) outlive this lookup call, and NSCache never retains the key it's given — only
  // the one already stored (built with `copy:YES` below, on a miss).
  TurboHtmlDocumentKey *lookupKey = [[TurboHtmlDocumentKey alloc] initWithBytes:html
                                                                          length:htmlLength
                                                                           style:style
                                                                            copy:NO];
  TurboHtmlCacheEntry *entry = [DocumentCache() objectForKey:lookupKey];
  std::shared_ptr<RichTextDocument> document;
  if (entry != nil) {
    document = entry.document;
  } else {
    document = RichTextDocumentBuilder::build(html, htmlLength, style);
    TurboHtmlDocumentKey *ownedKey = [[TurboHtmlDocumentKey alloc] initWithBytes:html
                                                                           length:htmlLength
                                                                            style:style
                                                                             copy:YES];
    entry = [[TurboHtmlCacheEntry alloc] initWithDocument:document];
    [DocumentCache() setObject:entry forKey:ownedKey cost:estimatedCost(document)];
  }
  return [entry layoutForWidth:width maxLines:maxLines];
}

std::shared_ptr<RichTextLayout> RichTextEngine::layout(NSString *html, const RichTextStyle &style, CGFloat width,
                                                        int maxLines) {
  if (html.length == 0 || width <= 0) return RichTextLayout::empty();
  Utf8View view = MakeUtf8View(html);
  return layout(view.data, view.length, style, width, maxLines);
}

void RichTextEngine::clear() {
  [DocumentCache() removeAllObjects];
}

} // namespace turbohtml

double TurboHtmlMeasure(const char *html, long htmlLength, const char *fontFamily, double fontSize,
                        double lineHeight, int numberOfLines, bool detectPhoneNumbers, double width,
                        double fontScale, double *outUsedWidth) {
  @autoreleasepool {
    turbohtml::RichTextStyle style = turbohtml::RichTextStyle::scaled(
        [NSString stringWithUTF8String:fontFamily] ?: @"Figtree", fontSize, lineHeight, detectPhoneNumbers,
        fontScale);
    // Raw bytes straight from the ShadowNode's `std::string` prop — no NSString round trip
    // on the hot path (see `RichTextEngine::layout`'s doc comment).
    auto layout =
        turbohtml::RichTextEngine::shared().layout(html, (size_t)htmlLength, style, (CGFloat)width, numberOfLines);
    if (outUsedWidth != nullptr) *outUsedWidth = (double)layout->usedWidth();
    return (double)layout->height();
  }
}
