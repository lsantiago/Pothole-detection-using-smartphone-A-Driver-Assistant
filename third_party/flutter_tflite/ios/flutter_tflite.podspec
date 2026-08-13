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
  # 2.2.0 (2020) doesn't recognize some op versions used by models exported
  # with modern (2023+) TF/Ultralytics toolchains - TfLiteInterpreterCreate
  # fails outright for them ("Failed to construct interpreter"), even though
  # the .tflite file itself loads fine. 2.14.0 is the newest stable release
  # as of this writing. TflitePlugin.mm now imports it framework-qualified
  # (#import <TensorFlowLiteC/TensorFlowLiteC.h>) instead of the old plain
  # #import "TensorFlowLiteC.h", which broke starting with 2.13.0's
  # repackaged multi-slice .xcframework headers - see TflitePlugin.mm.
  s.dependency 'TensorFlowLiteC', '2.14.0'

  s.ios.deployment_target = '9.0'
  s.static_framework = true
end

