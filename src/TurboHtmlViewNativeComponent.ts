import { codegenNativeComponent } from 'react-native';
import type {
  CodegenTypes as CT,
  ColorValue,
  HostComponent,
  ViewProps,
} from 'react-native';

export type LinkPressEvent = Readonly<{
  url: string;
  /** "link" for `<a href>`, "phone" for a detected phone number. */
  type: string;
}>;

export interface NativeProps extends ViewProps {
  html: string;
  /**
   * Family name (e.g. "Inter", "Kantumruy Pro") or PostScript name (e.g. "Figtree-Regular"),
   * resolved like RN `<Text fontFamily>`; bold/semibold/italic pick the closest face in that
   * family. Empty (default) = the system font.
   */
  fontFamily?: CT.WithDefault<string, ''>;
  fontSize?: CT.WithDefault<CT.Float, 14>;
  /** 0 (default) = the font's natural line height (≈ 1.2 × fontSize). */
  lineHeight?: CT.WithDefault<CT.Float, 0>;
  numberOfLines?: CT.WithDefault<CT.Int32, 0>;
  detectPhoneNumbers?: CT.WithDefault<boolean, true>;
  /** Weight for `<h1>`/`<h2>` (100–900); `<h3>`/`<h4>` use min(this, 600). */
  headingFontWeight?: CT.WithDefault<CT.Int32, 700>;
  /**
   * Body text color. Default: the platform's primary label color. Accepts any ColorValue,
   * including `PlatformColor` and `DynamicColorIOS` (resolved per light/dark at draw time).
   * Colors never trigger a re-layout.
   */
  color?: ColorValue;
  /** Color of links and detected phone numbers (text + underline). Default: platform link color. */
  linkColor?: ColorValue;
  onLinkPress?: CT.DirectEventHandler<LinkPressEvent>;
}

// `interfaceOnly`: codegen generates Props/EventEmitter only; the ShadowNode (with
// `measureContent`, so the view sizes itself in Yoga) and ComponentDescriptor are
// hand-written in cpp/react/renderer/components/TurboHtmlViewSpec.
export default codegenNativeComponent<NativeProps>('TurboHtmlView', {
  interfaceOnly: true,
}) as HostComponent<NativeProps>;
