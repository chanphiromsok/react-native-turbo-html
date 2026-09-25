#pragma once

#import <Foundation/Foundation.h>
#include <string>

// The tags `RichTextDocumentBuilder` treats specially. Everything else is `Other`, which
// the builder unwraps (children kept), matching `RenderHtml`.
//
// ObjC++ port of ios/Core/HTMLScanner.swift (see the Swift source in
// react-native-turbo-html-p for the original). Behavior must stay identical.
namespace turbohtml {

enum class HTMLTagKind {
  P, Li, H1, H2, H3, H4, H5, H6, Ul, Ol,
  B, Strong, I, Em, U, S, Del, A, Br,
  Head, Script, Style, Meta, Link,
  Div, Span,
  Other,
};

// A tag plus its raw (lowercased) name. Equality matches Swift's `HTMLTag: Equatable`:
// two tags are equal when their kind matches, and (for `Other`) their name also matches.
struct HTMLTag {
  HTMLTagKind kind = HTMLTagKind::Other;
  std::string name; // only meaningful when kind == Other

  static HTMLTag fromLowercasedName(const std::string &name);

  bool isVoid() const;

  bool operator==(const HTMLTag &other) const {
    if (kind != other.kind) return false;
    if (kind == HTMLTagKind::Other) return name == other.name;
    return true;
  }
  bool operator!=(const HTMLTag &other) const { return !(*this == other); }
};

// Receives scanner events; nesting/auto-closing is the sink's job.
class HTMLEventSink {
 public:
  virtual ~HTMLEventSink() = default;
  virtual void openTag(const HTMLTag &tag, NSString *_Nullable href, bool selfClosing) = 0;
  virtual void closeTag(const HTMLTag &tag) = 0;
  virtual void text(NSString *text) = 0;
};

// Single-pass, allocation-light HTML scanner over UTF-8 bytes (docs — see the package
// README's rendering-rules section).
//
// Every markup character is ASCII, so scanning bytes is correct for Khmer and any other
// UTF-8 text. Strings are only created for text runs, tag names and `a[href]` values.
// Tolerant like the old tokenizer: a `<` that doesn't start a tag is literal text;
// comments, `<!…>` and `<?…>` are skipped; `script`/`style` contents are skipped as raw
// text. Nesting/auto-closing is the sink's job.
class HTMLScanner {
 public:
  // `html`/`length` point at UTF-8 bytes (not necessarily NUL-terminated).
  static void scan(const char *html, size_t length, HTMLEventSink &sink);

  // Decodes `bytes[start..<end]` as UTF-8, resolving `&name;`, `&#123;` and `&#x1F;`. The
  // `;` search is capped at 12 bytes so malformed input stays linear.
  static NSString *decodeText(const uint8_t *bytes, size_t start, size_t end);
};

} // namespace turbohtml
