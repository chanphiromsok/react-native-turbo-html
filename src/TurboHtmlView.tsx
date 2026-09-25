import { Text, type TextProps } from 'react-native';
import type { LinkPressEvent } from './TurboHtmlViewNativeComponent';
import { stripHtml } from './stripHtml';

// Web has no Core Text / StaticLayout engine to size itself against, so this is a minimal
// fallback: the HTML is stripped to plain text (see `./stripHtml`) and rendered in a
// `<Text>`. It does not detect phone numbers or make links tappable —
// `detectPhoneNumbers`/`onLinkPress` are accepted for prop compatibility with the native
// component but are unused here.
export type TurboHtmlViewProps = Omit<TextProps, 'children'> & {
  html: string;
  fontFamily: string;
  fontSize: number;
  lineHeight: number;
  numberOfLines?: number;
  detectPhoneNumbers?: boolean;
  onLinkPress?: (event: { nativeEvent: LinkPressEvent }) => void;
};

export function TurboHtmlView({
  html,
  fontFamily,
  fontSize,
  lineHeight,
  numberOfLines,
  style,
  ...rest
}: TurboHtmlViewProps) {
  return (
    <Text
      {...rest}
      numberOfLines={
        numberOfLines && numberOfLines > 0 ? numberOfLines : undefined
      }
      style={[{ fontFamily, fontSize, lineHeight }, style]}
    >
      {stripHtml(html)}
    </Text>
  );
}
