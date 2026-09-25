#ifdef ANDROID

#include "TurboHtmlMeasurementsManager.h"

#include <fbjni/fbjni.h>
#include <folly/dynamic.h>
#include <react/jni/ReadableNativeMap.h>
#include <react/renderer/core/conversions.h>

using namespace facebook::jni;

namespace facebook::react {

Size TurboHtmlMeasurementsManager::measure(
    SurfaceId surfaceId,
    const TurboHtmlViewProps &props,
    const LayoutConstraints &layoutConstraints) const {
  const jni::global_ref<jobject> &fabricUIManager =
      contextContainer_->at<jni::global_ref<jobject>>("FabricUIManager");

  static auto measure = jni::findClassStatic("com/facebook/react/fabric/FabricUIManager")
                            ->getMethod<jlong(
                                jint,
                                jstring,
                                ReadableMap::javaobject,
                                ReadableMap::javaobject,
                                ReadableMap::javaobject,
                                jfloat,
                                jfloat,
                                jfloat,
                                jfloat)>("measure");

  // Only the layout-affecting props cross JNI.
  folly::dynamic serializedProps = folly::dynamic::object("html", props.html)("fontFamily", props.fontFamily)(
      "fontSize", props.fontSize)("lineHeight", props.lineHeight)("numberOfLines", props.numberOfLines)(
      "detectPhoneNumbers", props.detectPhoneNumbers)("headingFontWeight", props.headingFontWeight);
  local_ref<ReadableNativeMap::javaobject> propsRNM = ReadableNativeMap::newObjectCxxArgs(std::move(serializedProps));
  local_ref<ReadableMap::javaobject> propsRM = make_local(reinterpret_cast<ReadableMap::javaobject>(propsRNM.get()));

  local_ref<JString> componentName = make_jstring("TurboHtmlView");
  const auto minimumSize = layoutConstraints.minimumSize;
  const auto maximumSize = layoutConstraints.maximumSize;

  return yogaMeassureToSize(measure(
      fabricUIManager,
      surfaceId,
      componentName.get(),
      nullptr,
      propsRM.get(),
      nullptr,
      minimumSize.width,
      maximumSize.width,
      minimumSize.height,
      maximumSize.height));
}

} // namespace facebook::react

#endif // ANDROID
