#include "TurboHtmlViewSpec.h"

namespace facebook::react {

// Components only — no TurboModules.
std::shared_ptr<TurboModule> TurboHtmlViewSpec_ModuleProvider(
    const std::string & /*moduleName*/,
    const JavaTurboModule::InitParams & /*params*/) {
  return nullptr;
}

} // namespace facebook::react
