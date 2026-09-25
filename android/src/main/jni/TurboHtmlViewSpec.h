#pragma once

#include <ReactCommon/JavaTurboModule.h>
#include <ReactCommon/TurboModule.h>
#include <jsi/jsi.h>

/**
 * Replaces the codegen-generated `TurboHtmlViewSpec.h` (this directory comes first on the
 * include path, see CMakeLists.txt) so the app's autolinking.cpp — which includes
 * `<TurboHtmlViewSpec.h>` and registers `TurboHtmlViewComponentDescriptor` — sees our
 * hand-written descriptor with the measuring ShadowNode. Same approach as
 * react-native-screens (`rnscreens.h`).
 */
#include <react/renderer/components/TurboHtmlViewSpec/TurboHtmlViewComponentDescriptor.h>

namespace facebook::react {

JSI_EXPORT
std::shared_ptr<TurboModule> TurboHtmlViewSpec_ModuleProvider(
    const std::string &moduleName,
    const JavaTurboModule::InitParams &params);

} // namespace facebook::react
