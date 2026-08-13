#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html
#
Pod::Spec.new do |s|
  s.name             = 'flutter_tflite'
  s.version          = '1.1.2'
  s.summary          = 'A Flutter plugin for accessing TensorFlow Lite.'
  s.description      = <<-DESC
A Flutter plugin for accessing TensorFlow Lite. Supports both iOS and Android.
                       DESC
  s.homepage         = 'https://github.com/shaqian/flutter_tflite'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Qian Sha' => 'https://github.com/shaqian' }
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'
  # Only TflitePlugin.h (the FlutterPlugin entry point) needs to be public.
  # ios_image_load.h is an internal helper that #includes <vector> - modern
  # Xcode's explicit Clang modules require public headers to be
  # self-contained/module-safe, and a bare C++ standard header in a header
  # exposed to the (Objective-C) GeneratedPluginRegistrant.m import breaks
  # that with "'vector' file not found" / "Could not build module
  # 'flutter_tflite'". Keeping it private avoids it being pulled into the
  # module interface at all; it's still compiled and still visible to the
  # plugin's own .mm files via relative #include.
  s.public_header_files = 'Classes/TflitePlugin.h'
  s.dependency 'Flutter'
  # Unconstrained resolves to the latest TensorFlowLiteC (2.13.0 as of this
  # writing), which repackaged its headers and breaks this plugin's plain
  # #import "TensorFlowLiteC.h" in TflitePlugin.mm ("file not found"). Pin to
  # 2.2.0, the version the plugin author's own Podfile.lock was built and
  # tested against.
  s.dependency 'TensorFlowLiteC', '2.2.0'
  s.xcconfig = { 'USER_HEADER_SEARCH_PATHS' => '$(inherited) "${PODS_ROOT}/Headers/Private" "${PODS_ROOT}/Headers/Private/flutter_tflite" "${PODS_ROOT}/Headers/Public" "${PODS_ROOT}/Headers/Public/Flutter" "${PODS_ROOT}/Headers/Public/TensorFlowLite/tensorflow_lite" "${PODS_ROOT}/Headers/Public/flutter_tflite" "${PODS_ROOT}/TensorFlowLite/Frameworks/tensorflow_lite.framework/Headers" "${PODS_ROOT}/TensorFlowLiteC/Frameworks/TensorFlowLiteC.framework/Headers"' }

  s.ios.deployment_target = '9.0'
  s.static_framework = true
end

