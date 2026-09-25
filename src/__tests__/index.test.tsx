import { describe, expect, it } from '@jest/globals';
import { stripHtml } from '../stripHtml';

describe('stripHtml (web fallback markup stripping)', () => {
  it('strips tags and keeps text content', () => {
    expect(stripHtml('<p>Hello <b>world</b></p>')).toBe('Hello world');
  });

  it('turns <br> and block ends into line breaks', () => {
    expect(stripHtml('<p>a<br/>b</p><p>c</p>')).toBe('a\nb\nc');
  });

  it('renders list items with a bullet marker', () => {
    expect(stripHtml('<ul><li>one</li><li>two</li></ul>')).toBe('• one\n• two');
  });

  it('decodes common HTML entities', () => {
    expect(stripHtml('<p>Tom &amp; Jerry &hellip;</p>')).toBe('Tom & Jerry …');
  });

  it('drops script/style contents and comments', () => {
    expect(
      stripHtml('<script>evil()</script><!-- hidden --><p>visible</p>')
    ).toBe('visible');
  });
});

describe('package entry point', () => {
  it('exports TurboHtmlView', () => {
    const mod = require('../index');
    expect(mod.TurboHtmlView).toBeTruthy();
  });
});
