// Host-side tests for the platform-independent core (ios/Core/*): scanner, document
// builder, phone detection, Core Text layout, robustness and timing.
// ObjC++ port of tests/main.swift (react-native-turbo-html-p). Run: tests/run.sh
#import <CoreText/CoreText.h>
#import <Foundation/Foundation.h>

#include <chrono>
#include <cstdio>
#include <vector>

#import "../ios/Core/HTMLScanner.h"
#import "../ios/Core/RichTextDocument.h"
#import "../ios/Core/RichTextEngine.h"
#import "../ios/Core/RichTextLayout.h"

using turbohtml::HTMLEventSink;
using turbohtml::HTMLScanner;
using turbohtml::HTMLTag;
using turbohtml::RichTextDocument;
using turbohtml::RichTextDocumentBuilder;
using turbohtml::RichTextEngine;
using turbohtml::RichTextLayout;
using turbohtml::RichTextLayouter;
using turbohtml::RichTextPhoneDetector;
using turbohtml::RichTextStyle;

static int gFailures = 0;
static int gPasses = 0;

static void check(bool condition, NSString *message, int line) {
  if (condition) {
    gPasses += 1;
  } else {
    gFailures += 1;
    printf("FAIL (line %d): %s\n", line, message.UTF8String);
  }
}
#define CHECK(cond, msg) check((cond), (msg), __LINE__)

static void registerAppFonts(const char *dir) {
  NSString *dirPath = [NSString stringWithUTF8String:dir];
  NSArray<NSString *> *files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:dirPath error:nil];
  for (NSString *file in files) {
    if (![file.pathExtension isEqualToString:@"ttf"]) continue;
    NSURL *url = [NSURL fileURLWithPath:[dirPath stringByAppendingPathComponent:file]];
    CTFontManagerRegisterFontsForURL((__bridge CFURLRef)url, kCTFontManagerScopeProcess, NULL);
  }
}

// MARK: - Helpers

static std::vector<char> utf8Bytes(NSString *html) {
  NSUInteger len = [html lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
  std::vector<char> buffer(len);
  if (len > 0) {
    [html getBytes:buffer.data()
               maxLength:len
              usedLength:NULL
                encoding:NSUTF8StringEncoding
                 options:0
                   range:NSMakeRange(0, html.length)
          remainingRange:NULL];
  }
  return buffer;
}

static std::shared_ptr<RichTextDocument> makeDoc(NSString *html, const RichTextStyle &style) {
  std::vector<char> bytes = utf8Bytes(html);
  return RichTextDocumentBuilder::build(bytes.data(), bytes.size(), style);
}

static std::shared_ptr<RichTextLayout> makeLayout(NSString *html, CGFloat width, int lines, const RichTextStyle &style) {
  auto d = makeDoc(html, style);
  return RichTextLayouter::layout(*d, width, lines);
}

static NSArray<NSString *> *texts(const std::shared_ptr<RichTextDocument> &d) {
  NSMutableArray<NSString *> *out = [NSMutableArray array];
  for (const auto &p : d->paragraphs()) [out addObject:p.text.string];
  return out;
}

static NSString *fontNameAt(const std::shared_ptr<RichTextDocument> &d, NSInteger paragraph, NSUInteger index) {
  NSAttributedString *text = d->paragraphs()[(size_t)paragraph].text;
  CTFontRef font = (__bridge CTFontRef)[text attribute:(NSString *)kCTFontAttributeName atIndex:index effectiveRange:NULL];
  return (__bridge_transfer NSString *)CTFontCopyPostScriptName(font);
}

static RichTextLinkValue *_Nullable linkAt(const std::shared_ptr<RichTextDocument> &d, NSInteger paragraph, NSUInteger index) {
  NSAttributedString *text = d->paragraphs()[(size_t)paragraph].text;
  return [text attribute:turbohtml::RichTextAttribute::Link atIndex:index effectiveRange:NULL];
}

static NSArray<NSNumber *> *spacings(const std::shared_ptr<RichTextDocument> &d) {
  NSMutableArray<NSNumber *> *out = [NSMutableArray array];
  for (const auto &p : d->paragraphs()) [out addObject:@(p.spacingBefore)];
  return out;
}

static NSArray<NSString *> *prefixes(const std::shared_ptr<RichTextDocument> &d) {
  NSMutableArray<NSString *> *out = [NSMutableArray array];
  for (const auto &p : d->paragraphs()) [out addObject:p.prefix ? p.prefix.string : @""];
  return out;
}

int main(int argc, char *argv[]) {
  @autoreleasepool {
    const char *fontsDir = argc > 1 ? argv[1] : "./fonts";
    registerAppFonts(fontsDir);

    RichTextStyle style{@"Figtree", 14, 20, true};
    // The app passes headingFontWeight 600 for Khmer (its fontMapper maps font-bold → semibold).
    RichTextStyle khmerStyle{@"KantumruyPro", 14, 20, true, 600};

    // MARK: - Scanner / entities

    {
      auto d = makeDoc(@"<p>Tom &amp; Jerry &lt;3 &#39;x&#x27; &nbsp;&hellip; &unknown; &#xZZ; a < b</p>", style);
      NSArray *expected = @[ @"Tom & Jerry <3 'x' \u00A0\u2026 &unknown; &#xZZ; a < b" ];
      CHECK([texts(d) isEqualToArray:expected], @"entities + literal '<'");
    }
    {
      auto d = makeDoc(@"<!-- hidden --><p>a</p><script>var x = '<p>no</p>';</script><style>p{}</style><?xml x?><!DOCTYPE html><p>b</p>", style);
      CHECK([texts(d) isEqualToArray:(@[ @"a", @"b" ])], @"comments/script/style/doctype skipped");
    }
    {
      auto d = makeDoc(@"<P CLASS='x'>Upper</P><head><title>t</title></head>", style);
      CHECK([texts(d) isEqualToArray:(@[ @"Upper" ])], @"case-insensitive tags, head dropped");
    }

    // MARK: - Blocks and spacing (RenderHtml parity)

    {
      auto d = makeDoc(@"<p>a</p>\n<p>b</p>", style);
      CHECK([texts(d) isEqualToArray:(@[ @"a", @"b" ])], @"two paragraphs");
      CHECK([spacings(d) isEqualToArray:(@[ @0, @4 ])], @"top-level gap-1");
    }
    {
      auto d = makeDoc(@"<div><p>a</p><p>b</p></div><p>c</p>", style);
      CHECK([spacings(d) isEqualToArray:(@[ @0, @0, @4 ])], @"no gap inside generic wrapper");
    }
    {
      auto d = makeDoc(@"<ul><li>one</li><li>two</li><p>dropped</p></ul><ol><li>x</li><li>y</li></ol>", style);
      CHECK([texts(d) isEqualToArray:(@[ @"one", @"two", @"x", @"y" ])], @"list items only");
      CHECK([prefixes(d) isEqualToArray:(@[ @"\u2022", @"\u2022", @"1.", @"2." ])], @"list markers");
      CHECK([spacings(d) isEqualToArray:(@[ @0, @4, @4, @4 ])], @"list gaps");
    }
    {
      auto d = makeDoc(@"<p>a<p>b<ul><li>c<li>d</ul>", style);
      CHECK([texts(d) isEqualToArray:(@[ @"a", @"b", @"c", @"d" ])], @"implied closes");
    }
    {
      auto d = makeDoc(@"Hello <b>world</b>", style);
      CHECK([texts(d) isEqualToArray:(@[ @"Hello ", @"world" ])], @"bare text at block level splits like RenderHtml");
      CHECK([fontNameAt(d, 1, 0) isEqualToString:@"Figtree-Regular"], @"block-level <b> is unstyled like RenderHtml");
    }
    {
      auto d = makeDoc(@"<p>a<br>b<br/></p><p>line1\nline2</p>", style);
      CHECK([texts(d) isEqualToArray:(@[ @"a\u2028b\u2028", @"line1\u2028line2" ])], @"br and raw newlines");
    }

    // MARK: - Inline styles, headings, fonts

    {
      auto d = makeDoc(@"<p><b>B</b><strong>S</strong><i>I</i><u>U</u><s>X</s>n</p>", style);
      CHECK([fontNameAt(d, 0, 0) isEqualToString:@"Figtree-Bold"], @"b -> bold");
      CHECK([fontNameAt(d, 0, 1) isEqualToString:@"Figtree-Bold"], @"strong -> bold");
      NSAttributedString *text = d->paragraphs()[0].text;
      CTFontRef italic = (__bridge CTFontRef)[text attribute:(NSString *)kCTFontAttributeName atIndex:2 effectiveRange:NULL];
      CHECK(CTFontGetMatrix(italic).c != 0, @"i -> oblique matrix");
      CHECK([text attribute:turbohtml::RichTextAttribute::Underline atIndex:3 effectiveRange:NULL] != nil, @"u -> underline");
      CHECK([text attribute:turbohtml::RichTextAttribute::Strikethrough atIndex:4 effectiveRange:NULL] != nil, @"s -> strikethrough");
      CHECK([fontNameAt(d, 0, 5) isEqualToString:@"Figtree-Regular"], @"plain -> regular");
    }
    {
      auto d = makeDoc(@"<h1>a</h1><h3>b</h3><h5>c</h5>", style);
      CHECK([fontNameAt(d, 0, 0) isEqualToString:@"Figtree-Bold"], @"h1 bold");
      CHECK([fontNameAt(d, 1, 0) isEqualToString:@"Figtree-SemiBold"], @"h3 semibold");
      CHECK([fontNameAt(d, 2, 0) isEqualToString:@"Figtree-Regular"], @"h5 regular");
      NSAttributedString *text0 = d->paragraphs()[0].text;
      CTFontRef font0 = (__bridge CTFontRef)[text0 attribute:(NSString *)kCTFontAttributeName atIndex:0 effectiveRange:NULL];
      CHECK(CTFontGetSize(font0) == 14, @"headings keep base size (className wins in RenderHtml's cn())");

      auto k = makeDoc(@"<h1>\u1780</h1><p><b>\u1781</b></p>", khmerStyle);
      CHECK([fontNameAt(k, 0, 0) isEqualToString:@"KantumruyPro-SemiBold"], @"headingFontWeight 600 -> semibold h1");
      CHECK([fontNameAt(k, 1, 0) isEqualToString:@"KantumruyPro-Bold"], @"km inline bold -> bold");
    }

    // MARK: - Font resolution (any app's fonts, like RN <Text fontFamily>)

    {
      auto nameFor = [](NSString *family, NSString *html) {
        RichTextStyle s{family, 14, 20, true};
        return fontNameAt(makeDoc(html, s), 0, 0);
      };
      CHECK([nameFor(@"Figtree", @"<p><b>x</b></p>") isEqualToString:@"Figtree-Bold"], @"family name + bold");
      CHECK([nameFor(@"Figtree-Regular", @"<p><b>x</b></p>") isEqualToString:@"Figtree-Bold"],
            @"PostScript name + bold -> sibling face");
      CHECK([nameFor(@"Figtree-Bold", @"<p>x</p>") isEqualToString:@"Figtree-Regular"],
            @"PostScript name of a bold face + regular text -> regular sibling");
      NSString *kmFamily = (__bridge_transfer NSString *)CTFontCopyFamilyName(
          turbohtml::RichTextFonts::font(@"KantumruyPro-Regular", turbohtml::RichTextFontWeight::Regular, false, 14));
      NSString *kmMessage = [NSString stringWithFormat:@"real family name '%@' + bold", kmFamily];
      CHECK([nameFor(kmFamily, @"<p><b>x</b></p>") isEqualToString:@"KantumruyPro-Bold"], kmMessage);
      CHECK([nameFor(@"KantumruyPro", @"<h3>x</h3>") isEqualToString:@"KantumruyPro-SemiBold"],
            @"legacy <family>-<Weight> naming still resolves");
      NSString *system = nameFor(@"", @"<p>x</p>");
      NSString *systemMessage = [NSString stringWithFormat:@"empty family -> system font (%@)", system];
      CHECK((system.length > 0 && ![system hasPrefix:@"Figtree"] && ![system hasPrefix:@"Kantumruy"]), systemMessage);
      NSString *unknown = nameFor(@"NoSuchFontFamily", @"<p>x</p>");
      CHECK([unknown isEqualToString:system], @"unknown family -> system font");
      RichTextStyle defaults{};
      CHECK([defaults.fontFamily isEqualToString:@""] && defaults.headingFontWeight == 700,
            @"defaults: system font, bold headings");
    }

    // MARK: - Links and phones

    {
      auto d = makeDoc(
          @"<p><a href=\"https://turbo.com/x?a=1&amp;b=2\">site</a> <a href='javascript:alert(1)'>bad</a> <a href=\"www.x.com\">www</a></p>",
          style);
      CHECK([linkAt(d, 0, 0).url isEqualToString:@"https://turbo.com/x?a=1&b=2"], @"https link with decoded &amp;");
      CHECK(linkAt(d, 0, 5) == nil, @"javascript: rejected");
      CHECK([linkAt(d, 0, 9).url isEqualToString:@"https://www.x.com"], @"www. gets https://");
    }
    {
      NSArray<NSString *> *phones = @[ @"012 345 678", @"+855 12 345 678", @"012-345-678" ];
      for (NSString *p in phones) {
        NSString *text = [NSString stringWithFormat:@"call %@ now", p];
        CHECK(RichTextPhoneDetector::matches(text).size() == 1, ([NSString stringWithFormat:@"phone detected: %@", p]));
      }
      NSArray<NSString *> *notPhones = @[ @"2024-01-15", @"15-01-2024", @"10:30", @"$120,000", @"4x16m", @"1234567" ];
      for (NSString *p in notPhones) {
        NSString *text = [NSString stringWithFormat:@"x %@ y", p];
        CHECK(RichTextPhoneDetector::matches(text).empty(), ([NSString stringWithFormat:@"not a phone: %@", p]));
      }
      auto d = makeDoc(@"<p>Call 012 345 678</p>", style);
      RichTextLinkValue *tel = linkAt(d, 0, 6);
      CHECK(tel != nil && [tel.url isEqualToString:@"tel:012345678"] && tel.isPhone, @"tel link, whitespace stripped");

      // Real API content: Khmer editors put a zero-width space (U+200B) before each space.
      NSString *zwsp = @"<p>\u1791\u17B6\u1780\u17CB\u200B:\u200B 098\u200B 858\u200B 713/ 088 43 44 43 4</p>";
      auto kz = makeDoc(zwsp, style);
      NSString *kzText = kz->paragraphs()[0].text.string;
      NSUInteger firstAt = [kzText rangeOfString:@"098"].location;
      NSUInteger secondAt = [kzText rangeOfString:@"088"].location;
      RichTextLinkValue *first = linkAt(kz, 0, firstAt);
      RichTextLinkValue *second = linkAt(kz, 0, secondAt);
      CHECK(first != nil && [first.url isEqualToString:@"tel:098858713"], @"number with U+200B separators detected, tel digits only");
      CHECK(second != nil && [second.url isEqualToString:@"tel:0884344434"], @"second number on the same line still detected");
      CHECK(linkAt(kz, 0, [kzText rangeOfString:@"/"].location) == nil, @"slash between numbers is not linked");

      // Khmer numerals.
      auto kd = makeDoc(@"<p>\u179B\u17C1\u1781 \u17E0\u17E9\u17E8 \u17E8\u17E5\u17E8 \u17E7\u17E1\u17E3</p>", style);
      NSString *kdText = kd->paragraphs()[0].text.string;
      RichTextLinkValue *khmerDigits = linkAt(kd, 0, [kdText rangeOfString:@"\u17E0"].location);
      CHECK(khmerDigits != nil && [khmerDigits.url isEqualToString:@"tel:098858713"], @"Khmer digits detected, tel mapped to ASCII");
      CHECK(RichTextPhoneDetector::matches(@"\u17E2\u17E0\u17E2\u17E4-\u17E0\u17E1-\u17E1\u17E5").empty(),
            @"Khmer-digit date is not a phone");
      CHECK([RichTextPhoneDetector::telURL(@"+855\u200B 12 345 678") isEqualToString:@"tel:+85512345678"],
            @"leading + kept, invisible separators dropped");
      auto inLink = makeDoc(@"<p><a href=\"https://a.com\">012 345 678</a></p>", style);
      CHECK(linkAt(inLink, 0, 0).isPhone == NO, @"no phone detection inside <a>");
      auto bare = makeDoc(@"Call 012 345 678", style);
      CHECK(linkAt(bare, 0, 6) == nil, @"no phone detection in block-level text (RenderHtml parity)");
    }

    // MARK: - Layout

    {
      auto l = makeLayout(@"<p>Short line</p>", 343, 0, style);
      CHECK(l->height() == 20 && l->lineCount() == 1 && !l->truncated(), @"one line = lineHeight");
      auto two = makeLayout(@"<p>a</p><p>b</p>", 343, 0, style);
      CHECK(two->height() == 44 && two->lineCount() == 2, @"two blocks = 20 + 4 + 20");
      auto br = makeLayout(@"<p>a<br>b</p>", 343, 0, style);
      CHECK(br->lineCount() == 2 && br->height() == 40, @"br breaks line");
      auto blank = makeLayout(@"<p>a</p><p><br></p><p>b</p>", 343, 0, style);
      CHECK(blank->lineCount() == 3, @"<p><br></p> between blocks = one empty line (browser <br> semantics)");
      auto trailingBr = makeLayout(@"<p>a<br></p>", 343, 0, style);
      CHECK(trailingBr->lineCount() == 1 && trailingBr->height() == 20, @"trailing <br> adds no extra line");
      auto fourBr = makeLayout(@"<p>a</p><p><br><br><br><br></p><p>b</p>", 343, 0, style);
      CHECK(fourBr->lineCount() == 6, @"blank block in the middle keeps its 4 lines");
      auto padded = makeDoc(@"<p><br></p><p>&nbsp;</p><p>text</p><p><br><br><br><br></p><p><br></p><p>&nbsp; </p>", style);
      CHECK(padded->paragraphs().size() == 1 && [padded->plainText() isEqualToString:@"text"],
            @"leading/trailing empty editor blocks are trimmed");
      auto paddedLayout = makeLayout(@"<p>text</p><p><br><br><br><br></p><p><br></p>", 343, 0, style);
      CHECK(paddedLayout->height() == 20, @"trailing editor padding adds no height");
      auto empty = makeLayout(@"", 343, 0, style);
      CHECK(empty->height() == 0, @"empty html");
    }
    {
      NSMutableString *para = [NSMutableString string];
      for (int i = 0; i < 20; i++) [para appendString:@"The quick brown fox jumps over the lazy dog. "];
      NSString *long_ = [NSString stringWithFormat:@"<p>%@</p>", para];
      auto full = makeLayout(long_, 343, 0, style);
      CHECK(full->lineCount() > 5 && full->height() == (CGFloat)full->lineCount() * 20, @"wraps");
      auto cut = makeLayout(long_, 343, 2, style);
      CHECK(cut->lineCount() == 2 && cut->height() == 40 && cut->truncated(), @"numberOfLines=2 -> 40pt, truncated");
      CTLineRef lastLine = cut->lines().back().line;
      CFIndex glyphCount = CTLineGetGlyphCount(lastLine);
      CHECK(glyphCount > 0 && CTLineGetTypographicBounds(lastLine, NULL, NULL, NULL) <= 343.5, @"truncated line fits width");
      auto fits = makeLayout(@"<p>a</p><p>b</p>", 343, 1, style);
      CHECK(fits->truncated() && fits->lineCount() == 1, @"later block counts as truncation");
      auto exact = makeLayout(@"<p>a</p>", 343, 1, style);
      CHECK(!exact->truncated(), @"no truncation when everything fits");
    }
    {
      auto l = makeLayout(@"<p>Call 012 345 678 or <a href=\"https://turbo.com\">view</a></p>", 343, 0, style);
      CHECK(l->links().size() == 2, @"two link rects");
      CHECK(l->decorations().size() == 2, @"links underlined");
      if (!l->links().empty()) {
        const auto &first = l->links().front();
        RichTextLinkValue *hit = l->linkAt(CGPointMake(CGRectGetMidX(first.rect), CGRectGetMidY(first.rect)));
        CHECK(hit != nil && hit.isPhone, @"hit-test phone");
        CHECK(l->linkAt(CGPointMake(1, 10)) == nil, @"hit-test plain text");
      }
      NSMutableString *item = [NSMutableString string];
      for (int i = 0; i < 30; i++) [item appendString:@"wrap me "];
      NSString *listHtml = [NSString stringWithFormat:@"<ul><li>%@</li></ul>", item];
      auto list = makeLayout(listHtml, 343, 0, style);
      NSMutableSet<NSNumber *> *contentXs = [NSMutableSet set];
      for (const auto &placed : list->lines()) [contentXs addObject:@(placed.origin.x)];
      CHECK(contentXs.count == 2 && [contentXs containsObject:@0], @"hanging indent: marker at 0, content indented");
    }
    {
            auto l = makeLayout(@"<p>ផ្ទះល្វែងលក់បន្ទាន់ 😀👨‍👩‍👧 ok</p>", 120, 0, khmerStyle);
      CHECK(l->lineCount() >= 1 && l->height() == (CGFloat)l->lineCount() * 20, @"khmer + emoji layout");
    }

    // MARK: - Robustness

    {
      NSMutableString *manyP = [NSMutableString string];
      for (int i = 0; i < 5000; i++) [manyP appendString:@"<p>x</p>"];
      NSMutableString *manyB = [NSMutableString string];
      for (int i = 0; i < 5000; i++) [manyB appendString:@"<b>"];
      NSString *nul = [@"<p>" stringByAppendingString:[@"" stringByAppendingFormat:@"%C</p>", (unichar)0]];
      NSArray<NSString *> *inputs = @[
        @" ", @"<", @"<p", @"</p>", @"<p><b><i>unclosed", @"</b></i>stray", @"&", @"&#;", @"&#x;", @"&#99999999;",
        @"<a href>x</a>", @"<a href=>x</a>", @"<p/>", @"<<<>>>", nul, @"<ul><li></li></ul>", manyP, manyB
      ];
      for (NSString *input in inputs) {
        makeLayout(input, 343, 0, style);
        makeLayout(input, 343, 1, style);
      }
      CHECK(true, @"robustness inputs did not crash");
    }

    // MARK: - Timing (AC-13 / AC-14 on the Mac; device numbers differ)

    {
            NSString *para = @"<p>ផ្ទះល្វែងលក់បន្ទាន់ នៅជិតផ្សារ <strong>Tuol Kork</strong> តម្លៃ <em>$120,000</em> &amp; negotiable. Call 012 345 678 or <a href=\"https://turbo.com/x?a=1&amp;b=2\">view</a>.<br/>ទំហំ 4x16m, 3 bedrooms, 2 bathrooms.</p>";
      NSMutableString *fixture = [NSMutableString string];
      [fixture appendString:para];
      [fixture appendString:para];
      [fixture appendString:para];
      [fixture appendString:@"<ul><li>Parking</li><li>Near school</li></ul>"];

      auto timeIt = [](int iterations, void (^body)(void)) -> double {
        for (int i = 0; i < 20; i++) body();
        auto start = std::chrono::steady_clock::now();
        for (int i = 0; i < iterations; i++) body();
        auto end = std::chrono::steady_clock::now();
        double nanos = std::chrono::duration_cast<std::chrono::nanoseconds>(end - start).count();
        return nanos / iterations / 1000.0;
      };

      struct NullSink final : HTMLEventSink {
        size_t count = 0;
        void openTag(const HTMLTag &, NSString *, bool) override { count += 1; }
        void closeTag(const HTMLTag &) override { count += 1; }
        void text(NSString *t) override { count += [t lengthOfBytesUsingEncoding:NSUTF8StringEncoding]; }
      };

      std::vector<char> fixtureBytes = utf8Bytes(fixture);

      double scanTime = timeIt(5000, ^{
        NullSink sink;
        HTMLScanner::scan(fixtureBytes.data(), fixtureBytes.size(), sink);
      });
      double buildTime = timeIt(2000, ^{
        RichTextDocumentBuilder::build(fixtureBytes.data(), fixtureBytes.size(), style);
      });
      auto d = RichTextDocumentBuilder::build(fixtureBytes.data(), fixtureBytes.size(), style);
      double layoutTime = timeIt(1000, ^{
        RichTextLayouter::layout(*d, 343, 0);
      });
      // Measured via the raw-bytes overload, matching the real hot path
      // (`TurboHtmlMeasure`, which already holds the ShadowNode's raw `std::string` bytes)
      // rather than the `NSString *` convenience overload used by the component view's
      // (much less frequent) draw path — see RichTextEngine.h's doc comment.
      RichTextEngine::shared().layout(fixtureBytes.data(), fixtureBytes.size(), style, 343, 0);
      double hitTime = timeIt(10000, ^{
        RichTextEngine::shared().layout(fixtureBytes.data(), fixtureBytes.size(), style, 343, 0);
      });

      printf("timing (fixture %lu UTF-16 chars): scan %.1f \u00b5s, build %.1f \u00b5s, layout %.1f \u00b5s, cache hit %.2f \u00b5s\n",
             (unsigned long)fixture.length, scanTime, buildTime, layoutTime, hitTime);
    }

    printf("%d passed, %d failed\n", gPasses, gFailures);
    return gFailures == 0 ? 0 : 1;
  }
}
