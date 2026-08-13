import 'dart:math' as math;

/// Decodes raw SSD box_encodings + class_predictions (using the given
/// anchors) into detections, and runs single-class Non-Max Suppression.
///
/// This is a from-scratch port of the box-decode math and the
/// use_regular_nms=false ("fast") NMS path from TensorFlow Lite's
/// TFLite_Detection_PostProcess custom op
/// (tensorflow/lite/kernels/detection_postprocess.cc), specialized for
/// num_classes=1 (both models this app ships have exactly one non-background
/// class, "pothole"). It exists because that op is compiled into
/// TensorFlowLiteC but not registered by its interpreter on iOS, so models
/// using it get Invoke() failures there - see
/// third_party/flutter_tflite/ios/Classes/TflitePlugin.mm's
/// dumpRawSSDOutputs/detectObjectRawOn{Image,Frame} and this app's
/// assets/*_raw.tflite (the same models with that op stripped out and its
/// 3 input tensors exposed as the graph's outputs instead).
///
/// Verified against a reference NumPy port of the same op run through the
/// real (unmodified-math) TFLite interpreter before being ported here -
/// see the box coordinate math below, which matches
/// DecodeCenterSizeBoxes in detection_postprocess.cc exactly.
class SsdDetection {
  final double ymin, xmin, ymax, xmax;
  final double score;

  const SsdDetection({
    required this.ymin,
    required this.xmin,
    required this.ymax,
    required this.xmax,
    required this.score,
  });
}

List<SsdDetection> decodeSsdDetections({
  required List<double> boxEncodings, // flat [numBoxes * 4]: y, x, h, w
  required List<double>
      classScores, // flat [numBoxes * 2]: background, pothole
  required List<double> anchors, // flat [numBoxes * 4]: ycenter, xcenter, h, w
  double yScale = 10.0,
  double xScale = 10.0,
  double hScale = 5.0,
  double wScale = 5.0,
  double nmsIouThreshold = 0.6,
  // Both models' own custom_options set this close to 0 - they expect the
  // caller to pick a display/decision threshold rather than filtering
  // in the op itself, matching the `threshold` argument the native
  // SSDMobileNet path took on Android. 0.4 mirrors that path's default.
  double nmsScoreThreshold = 0.4,
  int maxDetections = 10,
}) {
  final numBoxes = anchors.length ~/ 4;
  final ymin = List<double>.filled(numBoxes, 0);
  final xmin = List<double>.filled(numBoxes, 0);
  final ymax = List<double>.filled(numBoxes, 0);
  final xmax = List<double>.filled(numBoxes, 0);
  final scores = List<double>.filled(numBoxes, 0);

  for (int i = 0; i < numBoxes; i++) {
    final by = boxEncodings[i * 4 + 0];
    final bx = boxEncodings[i * 4 + 1];
    final bh = boxEncodings[i * 4 + 2];
    final bw = boxEncodings[i * 4 + 3];
    final ay = anchors[i * 4 + 0];
    final ax = anchors[i * 4 + 1];
    final ah = anchors[i * 4 + 2];
    final aw = anchors[i * 4 + 3];

    final ycenter = by / yScale * ah + ay;
    final xcenter = bx / xScale * aw + ax;
    final halfH = 0.5 * math.exp(bh / hScale) * ah;
    final halfW = 0.5 * math.exp(bw / wScale) * aw;

    ymin[i] = ycenter - halfH;
    xmin[i] = xcenter - halfW;
    ymax[i] = ycenter + halfH;
    xmax[i] = xcenter + halfW;

    // classScores columns are [background, pothole] (num_classes=1, so
    // there's only ever this one non-background class to consider).
    scores[i] = classScores[i * 2 + 1];
  }

  final keepIndices = <int>[
    for (int i = 0; i < numBoxes; i++)
      if (scores[i] >= nmsScoreThreshold) i
  ];
  keepIndices.sort((a, b) => scores[b].compareTo(scores[a]));

  final active = <int, bool>{for (final i in keepIndices) i: true};
  final selected = <int>[];
  for (int idx = 0; idx < keepIndices.length; idx++) {
    if (selected.length >= maxDetections) break;
    final i = keepIndices[idx];
    if (active[i] != true) continue;
    selected.add(i);
    for (int jdx = idx + 1; jdx < keepIndices.length; jdx++) {
      final j = keepIndices[jdx];
      if (active[j] == true &&
          _iou(ymin[i], xmin[i], ymax[i], xmax[i], ymin[j], xmin[j], ymax[j],
                  xmax[j]) >
              nmsIouThreshold) {
        active[j] = false;
      }
    }
  }

  return [
    for (final i in selected)
      SsdDetection(
          ymin: ymin[i], xmin: xmin[i], ymax: ymax[i], xmax: xmax[i], score: scores[i])
  ];
}

double _iou(double aYmin, double aXmin, double aYmax, double aXmax,
    double bYmin, double bXmin, double bYmax, double bXmax) {
  final areaA = math.max(0.0, aYmax - aYmin) * math.max(0.0, aXmax - aXmin);
  final areaB = math.max(0.0, bYmax - bYmin) * math.max(0.0, bXmax - bXmin);
  if (areaA <= 0 || areaB <= 0) return 0.0;
  final interYmin = math.max(aYmin, bYmin);
  final interXmin = math.max(aXmin, bXmin);
  final interYmax = math.min(aYmax, bYmax);
  final interXmax = math.min(aXmax, bXmax);
  final interArea =
      math.max(0.0, interYmax - interYmin) * math.max(0.0, interXmax - interXmin);
  return interArea / (areaA + areaB - interArea);
}

/// Converts decoded detections into the same {rect: {x,y,w,h}, detectedClass,
/// confidenceInClass} shape the app's UI code (renderBoxes, the alert logic
/// in live_camera.dart) already expects from the native SSDMobileNet parser,
/// so none of that code needs to change.
List<Map<String, dynamic>> ssdDetectionsToRecognitions(
    List<SsdDetection> detections) {
  return [
    for (final d in detections)
      {
        'rect': {
          'x': d.xmin,
          'y': d.ymin,
          'w': math.min(1 - d.xmin, d.xmax - d.xmin),
          'h': math.min(1 - d.ymin, d.ymax - d.ymin),
        },
        'confidenceInClass': d.score,
        'detectedClass': 'pothole',
        // Callers (setRecognitions in live_camera.dart/static_image.dart)
        // read these unconditionally from the native SSDMobileNet parser's
        // output shape; not measured here, so just present as 0.
        'inferenceTime': 0,
        'preProcessingTime': 0,
      }
  ];
}

/// Converts the {"boxes": [...], "scores": [...], "anchors": [...]} map
/// returned by Tflite.detectObjectRawOnImage/OnFrame (flat lists of
/// num-typed values from the platform channel) into the double lists
/// decodeSsdDetections expects.
List<double> toDoubleList(List<dynamic>? raw) =>
    raw?.map((e) => (e as num).toDouble()).toList() ?? const <double>[];
