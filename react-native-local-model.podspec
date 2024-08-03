require "json"

package = JSON.parse(File.read(File.join(__dir__, "package.json")))
folly_compiler_flags = '-DFOLLY_NO_CONFIG -DFOLLY_MOBILE=1 -DFOLLY_USE_LIBCPP=1 -Wno-comma -Wno-shorten-64-to-32 -Wno-int-conversion'
additional_compiler_flags = ' -Wno-unused-function -Wno-shorten-64-to-32 -Wno-int-conversion'

Pod::Spec.new do |s|
  s.name         = "react-native-local-model"
  s.version      = package["version"]
  s.summary      = package["description"]
  s.homepage     = package["homepage"]
  s.license      = package["license"]
  s.authors      = package["author"]

  s.platforms    = { :ios => min_ios_version_supported }
  s.source       = { :git => "https://github.com/ponikar/react-native-local-model.git", :tag => "#{s.version}" }

  s.source_files = "ios/**/*.{h,m,mm,cpp}"

  # Use install_modules_dependencies helper to install the dependencies if React Native version >=0.71.0.
  if respond_to?(:install_modules_dependencies, true)
    install_modules_dependencies(s)
  else
    s.dependency "React-Core"

    # Don't install the dependencies when we run `pod install` in the old architecture.
    if ENV['RCT_NEW_ARCH_ENABLED'] == '1' then
      s.compiler_flags = folly_compiler_flags + additional_compiler_flags + " -DRCT_NEW_ARCH_ENABLED=1"
      s.pod_target_xcconfig    = {
          "HEADER_SEARCH_PATHS" => "\"$(PODS_ROOT)/boost\" \"${PODS_ROOT}/Headers/Public/React-hermes\" \"${PODS_ROOT}/Headers/Public/hermes-engine\"",
          "OTHER_CPLUSPLUSFLAGS" => "-DFOLLY_NO_CONFIG -DFOLLY_MOBILE=1 -DFOLLY_USE_LIBCPP=1" + additional_compiler_flags,
          "CLANG_CXX_LANGUAGE_STANDARD" => "c++17"
      }
      s.dependency "React-Codegen"
      s.dependency "RCT-Folly"
      s.dependency "RCTRequired"
      s.dependency "RCTTypeSafety"
      s.dependency "ReactCommon/turbomodule/core"
    end
  end

  # If you have any resources to include
  # s.resource_bundles = {
  #   'react-native-local-model' => ['ios/**/*.xib']
  # }

  # If you need to specify a module map
  # s.module_map = "ios/react-native-local-model.modulemap"

  # If you need to specify any additional build settings
  s.pod_target_xcconfig = {
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++17',
    'HEADER_SEARCH_PATHS' => '$(PODS_ROOT)/boost $(SRCROOT)/../ios',
    'OTHER_CPLUSPLUSFLAGS' => '-DGGML_USE_ACCELERATE',
    'OTHER_LDFLAGS' => '-framework Accelerate',
    'ENABLE_BITCODE' => 'NO'
  }

  # If you need to specify any user-facing frameworks
  # s.frameworks = 'UIKit', 'MapKit'

  # If you need to specify a minimum deployment target
  s.ios.deployment_target = '12.0'

  # If you need to disable bitcode
  s.pod_target_xcconfig = { 'ENABLE_BITCODE' => 'NO' }
end