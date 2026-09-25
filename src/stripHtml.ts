// Minimal, dependency-free HTML-to-plain-text conversion used by the web fallback
// (`TurboHtmlView.tsx`). Not a full port of the native rendering rules — just enough to
// show readable text where the real Core Text / StaticLayout engine isn't available.
// Kept in its own (non-platform-suffixed) module so it can be unit tested directly.

const NAMED_ENTITIES: Record<string, string> = {
  amp: '&',
  lt: '<',
  gt: '>',
  quot: '"',
  apos: "'",
  nbsp: ' ',
  ndash: '–',
  mdash: '—',
  hellip: '…',
  bull: '•',
};

export function decodeEntities(text: string): string {
  return text.replace(
    /&(#x?[0-9a-fA-F]+|[a-zA-Z]+);/g,
    (match, body: string) => {
      if (body[0] === '#') {
        const codePoint =
          body[1] === 'x' || body[1] === 'X'
            ? parseInt(body.slice(2), 16)
            : parseInt(body.slice(1), 10);
        return Number.isNaN(codePoint)
          ? match
          : String.fromCodePoint(codePoint);
      }
      return NAMED_ENTITIES[body] ?? match;
    }
  );
}

// Strips markup down to plain text, keeping list markers and block/line breaks readable.
export function stripHtml(html: string): string {
  let text = html
    .replace(/<(script|style)[^>]*>[\s\S]*?<\/\1>/gi, '')
    .replace(/<!--[\s\S]*?-->/g, '')
    .replace(/<br\s*\/?>/gi, '\n')
    .replace(/<li[^>]*>/gi, '• ')
    .replace(/<\/(p|div|li|ul|ol|h[1-6])>/gi, '\n')
    .replace(/<[^>]+>/g, '');
  text = decodeEntities(text);
  return text
    .replace(/[ \t]+\n/g, '\n')
    .replace(/\n{3,}/g, '\n\n')
    .trim();
}
