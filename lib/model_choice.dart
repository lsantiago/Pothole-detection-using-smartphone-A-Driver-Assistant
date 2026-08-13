/// Which pothole detection model a detection screen should use.
///
/// yolo is iOS-only for now: it needs the raw single-tensor passthrough
/// added to third_party/flutter_tflite's iOS plugin
/// (detectObjectRawSingleOn{Image,Frame}), which hasn't been added to the
/// Android side. The model picker in notification_permission_screen.dart
/// only offers it on iOS.
enum PotholeModel { ssd, yolo }
