#import "HTMLScanner.h"

#include <unordered_map>
#include <unordered_set>

namespace turbohtml {

namespace {

inline bool isAlpha(uint8_t c) {
  return (c >= 0x61 && c <= 0x7A) || (c >= 0x41 && c <= 0x5A);
}

inline bool isNameByte(uint8_t c) {
  return isAlpha(c) || (c >= 0x30 && c <= 0x39) || c == '-' || c == ':' || c == '_';
}

inline bool isSpace(uint8_t c) {
  return c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D || c == 0x0C;
}

inline uint8_t lower(uint8_t c) {
  return (c >= 0x41 && c <= 0x5A) ? (uint8_t)(c | 0x20) : c;
}

std::string lowercasedString(const uint8_t *b, size_t start, size_t end) {
  std::string out;
  out.resize(end - start);
  for (size_t k = start; k < end; k++) out[k - start] = (char)lower(b[k]);
  return out;
}

// Case-sensitive literal match (literal already lowercase where relevant to the caller).
bool matches(const uint8_t *b, size_t n, size_t index, const char *literal, size_t count) {
  if (index + count > n) return false;
  for (size_t k = 0; k < count; k++) {
    if (b[index + k] != (uint8_t)literal[k]) return false;
  }
  return true;
}

// Finds a case-sensitive literal starting at/after `from`. Returns SIZE_MAX if absent.
size_t find(const uint8_t *b, size_t n, size_t from, const char *literal, size_t count) {
  for (size_t k = from; k + count <= n; k++) {
    if (matches(b, n, k, literal, count)) return k;
  }
  return SIZE_MAX;
}

// Case-insensitive search for an ASCII, already-lowercase `literal`.
size_t findLowercased(const uint8_t *b, size_t n, size_t from, const char *literal, size_t count) {
  for (size_t k = from; k + count <= n; k++) {
    bool ok = true;
    for (size_t m = 0; m < count; m++) {
      if (lower(b[k + m]) != (uint8_t)literal[m]) { ok = false; break; }
    }
    if (ok) return k;
  }
  return SIZE_MAX;
}

size_t findByte(const uint8_t *b, size_t n, size_t from, uint8_t byte) {
  for (size_t k = from; k < n; k++) {
    if (b[k] == byte) return k;
  }
  return SIZE_MAX;
}

bool equalsLowercased(const uint8_t *b, size_t start, size_t end, const char *literal, size_t count) {
  if (end - start != count) return false;
  for (size_t k = 0; k < count; k++) {
    if (lower(b[start + k]) != (uint8_t)literal[k]) return false;
  }
  return true;
}

const std::unordered_set<std::string> &otherVoidElements() {
  static const std::unordered_set<std::string> set = {
      "img", "hr", "input", "area", "base", "col", "embed", "source", "track", "wbr"};
  return set;
}

const std::unordered_map<std::string, uint32_t> &namedEntities() {
  static const std::unordered_map<std::string, uint32_t> map = {
      {"amp", 0x26},    {"lt", 0x3C},     {"gt", 0x3E},      {"quot", 0x22},   {"apos", 0x27},
      {"nbsp", 0xA0},   {"ndash", 0x2013},{"mdash", 0x2014}, {"hellip", 0x2026},{"bull", 0x2022},
      {"middot", 0xB7}, {"lsquo", 0x2018},{"rsquo", 0x2019}, {"ldquo", 0x201C}, {"rdquo", 0x201D},
      {"laquo", 0xAB},  {"raquo", 0xBB},  {"copy", 0xA9},    {"reg", 0xAE},     {"trade", 0x2122},
      {"euro", 0x20AC}, {"deg", 0xB0},    {"times", 0xD7}};
  return map;
}

// Appends the UTF-8 encoding of a Unicode scalar to `out`.
void appendUTF8(std::string &out, uint32_t scalar) {
  if (scalar <= 0x7F) {
    out.push_back((char)scalar);
  } else if (scalar <= 0x7FF) {
    out.push_back((char)(0xC0 | (scalar >> 6)));
    out.push_back((char)(0x80 | (scalar & 0x3F)));
  } else if (scalar <= 0xFFFF) {
    out.push_back((char)(0xE0 | (scalar >> 12)));
    out.push_back((char)(0x80 | ((scalar >> 6) & 0x3F)));
    out.push_back((char)(0x80 | (scalar & 0x3F)));
  } else {
    out.push_back((char)(0xF0 | (scalar >> 18)));
    out.push_back((char)(0x80 | ((scalar >> 12) & 0x3F)));
    out.push_back((char)(0x80 | ((scalar >> 6) & 0x3F)));
    out.push_back((char)(0x80 | (scalar & 0x3F)));
  }
}

// Decodes an entity body (without `&`/`;`) to a Unicode scalar, or 0 if unrecognized.
// Returns true and sets `outScalar` on success (0xFFFD counts as success, like Swift).
bool entityScalar(const uint8_t *b, size_t start, size_t end, uint32_t *outScalar) {
  if (b[start] == '#') {
    size_t k = start + 1;
    uint32_t radix = 10;
    if (k < end && lower(b[k]) == 'x') {
      radix = 16;
      k += 1;
    }
    if (k >= end) return false;
    uint64_t value = 0;
    while (k < end) {
      uint8_t c = lower(b[k]);
      uint32_t digit;
      if (c >= 0x30 && c <= 0x39) {
        digit = c - 0x30;
      } else if (radix == 16 && c >= 0x61 && c <= 0x66) {
        digit = c - 0x61 + 10;
      } else {
        return false;
      }
      value = value * radix + digit;
      if (value > 0x10FFFF) {
        *outScalar = 0xFFFD;
        return true;
      }
      k += 1;
    }
    if (value == 0 || (value >= 0xD800 && value <= 0xDFFF)) {
      *outScalar = 0xFFFD;
    } else {
      *outScalar = (uint32_t)value;
    }
    return true;
  }

  auto it = namedEntities().find(lowercasedString(b, start, end));
  if (it == namedEntities().end()) return false;
  *outScalar = it->second;
  return true;
}

} // namespace

HTMLTag HTMLTag::fromLowercasedName(const std::string &name) {
  static const std::unordered_map<std::string, HTMLTagKind> kMap = {
      {"p", HTMLTagKind::P},     {"li", HTMLTagKind::Li},   {"h1", HTMLTagKind::H1},
      {"h2", HTMLTagKind::H2},   {"h3", HTMLTagKind::H3},   {"h4", HTMLTagKind::H4},
      {"h5", HTMLTagKind::H5},   {"h6", HTMLTagKind::H6},   {"ul", HTMLTagKind::Ul},
      {"ol", HTMLTagKind::Ol},   {"b", HTMLTagKind::B},     {"strong", HTMLTagKind::Strong},
      {"i", HTMLTagKind::I},     {"em", HTMLTagKind::Em},   {"u", HTMLTagKind::U},
      {"s", HTMLTagKind::S},     {"del", HTMLTagKind::Del}, {"a", HTMLTagKind::A},
      {"br", HTMLTagKind::Br},   {"head", HTMLTagKind::Head}, {"script", HTMLTagKind::Script},
      {"style", HTMLTagKind::Style}, {"meta", HTMLTagKind::Meta}, {"link", HTMLTagKind::Link},
      {"div", HTMLTagKind::Div}, {"span", HTMLTagKind::Span},
  };
  auto it = kMap.find(name);
  HTMLTag tag;
  if (it != kMap.end()) {
    tag.kind = it->second;
  } else {
    tag.kind = HTMLTagKind::Other;
    tag.name = name;
  }
  return tag;
}

bool HTMLTag::isVoid() const {
  switch (kind) {
    case HTMLTagKind::Br:
    case HTMLTagKind::Meta:
    case HTMLTagKind::Link:
      return true;
    case HTMLTagKind::Other:
      return otherVoidElements().count(name) > 0;
    default:
      return false;
  }
}

NSString *HTMLScanner::decodeText(const uint8_t *b, size_t start, size_t end) {
  if (start >= end) return @"";

  size_t firstAmpersand = SIZE_MAX;
  for (size_t k = start; k < end; k++) {
    if (b[k] == '&') { firstAmpersand = k; break; }
  }
  if (firstAmpersand == SIZE_MAX) {
    return [[NSString alloc] initWithBytes:b + start length:(end - start) encoding:NSUTF8StringEncoding] ?: @"";
  }

  std::string out;
  out.reserve(end - start);
  out.append((const char *)b + start, firstAmpersand - start);

  size_t k = firstAmpersand;
  while (k < end) {
    uint8_t c = b[k];
    if (c != '&') {
      out.push_back((char)c);
      k += 1;
      continue;
    }

    size_t semi = SIZE_MAX;
    size_t m = k + 1;
    while (m < end && m - k <= 12) {
      if (b[m] == ';') { semi = m; break; }
      if (b[m] == '&' || b[m] == '<' || isSpace(b[m])) break;
      m += 1;
    }

    uint32_t scalar = 0;
    if (semi != SIZE_MAX && semi > k + 1 && entityScalar(b, k + 1, semi, &scalar)) {
      appendUTF8(out, scalar);
      k = semi + 1;
    } else {
      out.push_back((char)c);
      k += 1;
    }
  }

  return [[NSString alloc] initWithBytes:out.data() length:out.size() encoding:NSUTF8StringEncoding] ?: @"";
}

void HTMLScanner::scan(const char *htmlBytes, size_t length, HTMLEventSink &sink) {
  const uint8_t *b = (const uint8_t *)htmlBytes;
  const size_t n = length;
  size_t i = 0;
  size_t textStart = 0;

  auto flushText = [&](size_t end) {
    if (end > textStart) {
      sink.text(HTMLScanner::decodeText(b, textStart, end));
    }
  };

  while (i < n) {
    if (b[i] != '<') {
      i += 1;
      continue;
    }

    if (matches(b, n, i, "<!--", 4)) {
      flushText(i);
      size_t close = find(b, n, i + 4, "-->", 3);
      i = (close == SIZE_MAX) ? n : close + 3;
      textStart = i;
      continue;
    }

    if (i + 1 < n && (b[i + 1] == '!' || b[i + 1] == '?')) {
      flushText(i);
      size_t gtPos = findByte(b, n, i, '>');
      i = (gtPos == SIZE_MAX) ? n : gtPos + 1;
      textStart = i;
      continue;
    }

    size_t j = i + 1;
    bool closing = j < n && b[j] == '/';
    if (closing) j += 1;

    // Not a tag (e.g. "a < b"): keep the "<" as part of the surrounding text.
    if (!(j < n && isAlpha(b[j]))) {
      i += 1;
      continue;
    }

    flushText(i);

    size_t nameStart = j;
    while (j < n && isNameByte(b[j])) j += 1;
    HTMLTag tag = HTMLTag::fromLowercasedName(lowercasedString(b, nameStart, j));

    NSString *href = nil;
    bool selfClosing = false;

    while (j < n && b[j] != '>') {
      if (isSpace(b[j])) {
        j += 1;
        continue;
      }
      if (b[j] == '/') {
        selfClosing = true;
        j += 1;
        continue;
      }

      size_t attrStart = j;
      while (j < n && !isSpace(b[j]) && b[j] != '=' && b[j] != '>' && b[j] != '/') j += 1;
      size_t attrEnd = j;
      while (j < n && isSpace(b[j])) j += 1;

      long long valueStart = -1;
      long long valueEnd = -1;
      if (j < n && b[j] == '=') {
        j += 1;
        while (j < n && isSpace(b[j])) j += 1;
        if (j < n && (b[j] == '"' || b[j] == '\'')) {
          uint8_t quote = b[j];
          j += 1;
          valueStart = (long long)j;
          while (j < n && b[j] != quote) j += 1;
          valueEnd = (long long)j;
          if (j < n) j += 1;
        } else {
          valueStart = (long long)j;
          while (j < n && !isSpace(b[j]) && b[j] != '>') j += 1;
          valueEnd = (long long)j;
        }
        selfClosing = false;
      }

      if (tag.kind == HTMLTagKind::A && !closing && valueStart >= 0 &&
          equalsLowercased(b, attrStart, attrEnd, "href", 4)) {
        href = HTMLScanner::decodeText(b, (size_t)valueStart, (size_t)valueEnd);
      }
    }

    if (j < n) j += 1; // consume ">"
    i = j;
    textStart = i;

    if (closing) {
      sink.closeTag(tag);
      continue;
    }

    sink.openTag(tag, href, selfClosing || tag.isVoid());

    // Raw-text elements: skip to their closing tag; the closing tag itself is then
    // scanned normally so the sink sees a balanced open/close.
    if (tag.kind == HTMLTagKind::Script || tag.kind == HTMLTagKind::Style) {
      size_t closeAt = tag.kind == HTMLTagKind::Script ? findLowercased(b, n, i, "</script", 8)
                                                        : findLowercased(b, n, i, "</style", 7);
      i = (closeAt == SIZE_MAX) ? n : closeAt;
      textStart = i;
    }
  }

  flushText(n);
}

} // namespace turbohtml
