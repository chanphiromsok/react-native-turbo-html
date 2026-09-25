require "json"

package = JSON.parse(File.read(File.join(__dir__, "package.json")))

Pod::Spec.new do |s|
  s.name         = "TurboHtml"
  s.version      = package["version"]
  s.summary      = package["description"]
  s.homepage     = package["homepage"]
  s.license      = package["license"]
  s.authors      = package["author"]

  s.platforms    = { :ios => min_ios_version_supported }
  s.source       = { :git => "https://github.com/chanphiromsok/react-native-turbo-html.git", :tag => "#{s.version}" }

  # Objective-C++ view + Core Text engine, plus the hand-written measuring ShadowNode
  # (shared with Android) under the package-root cpp/ folder.
  s.source_files = ["ios/**/*.{h,m,mm}", "cpp/**/*.{h,cpp}"]
  # C++ headers stay private/project-only so they are never exposed as a public umbrella
  # header (which would otherwise pull React's C++ headers into consumers' module maps).
  s.private_header_files = "ios/**/*.h"
  s.project_header_files = "cpp/**/*.h"
  s.pod_target_xcconfig = {
    "HEADER_SEARCH_PATHS" => "\"$(PODS_TARGET_SRCROOT)/cpp\"",
    "DEFINES_MODULE" => "YES"
  }

  install_modules_dependencies(s)
end
