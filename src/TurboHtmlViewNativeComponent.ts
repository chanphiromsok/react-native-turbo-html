import { codegenNativeComponent } from 'react-native';
import type {
  CodegenTypes as CT,
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
  fontFamily: string;
  fontSize: CT.Float;
  lineHeight: CT.Float;
  numberOfLines?: CT.WithDefault<CT.Int32, 0>;
  detectPhoneNumbers?: CT.WithDefault<boolean, true>;
  onLinkPress?: CT.DirectEventHandler<LinkPressEvent>;
}

// `interfaceOnly`: codegen generates Props/EventEmitter only; the ShadowNode (with
// `measureContent`, so the view sizes itself in Yoga) and ComponentDescriptor are
// hand-written in cpp/react/renderer/components/TurboHtmlViewSpec.
export default codegenNativeComponent<NativeProps>('TurboHtmlView', {
  interfaceOnly: true,
}) as HostComponent<NativeProps>;
