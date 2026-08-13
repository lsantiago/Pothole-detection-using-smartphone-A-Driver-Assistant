import 'dart:math' as math;

/// Decodes a raw YOLOv8 (Ultralytics) single-class detection output into
/// detections and runs NMS.
///
/// The exported .tflite's single output tensor has shape [1, 5, numAnchors]:
/// rows 0-3 are box center/size (cx, cy, w, h), already normalized to [0,1]
/// relative to the model's input size, and row 4 is the (already
/// sigmoid-activated) confidence for the single "pothole" class - verified
/// empirically by running the real model through the standard TFLite
/// interpreter and inspecting each row's value range before writing this.
/// No anchor-box decoding is needed here (unlike the SSD models - see
/// ssd_postprocess.dart): YOLOv8 predicts box coordinates directly per grid
/// cell, it doesn't regress offsets against a fixed anchor set.
class YoloDetection {
  final double ymin, xmin, ymax, xmax;
  final double score;

  const YoloDetection({
    required this.ymin,
    required this.xmin,
    required this.ymax,
    required this.xmax,
    required this.score,
  });
}

List<YoloDetection> decodeYoloDetections({
  required List<double> output, // flat [5 * numAnchors]: row-major (row, anchor)
  required int numAnchors,
  double confidenceThreshold = 0.25, // Ultralytics' own default
  double nmsIouThreshold = 0.45, // Ultralytics' own default
  int maxDetections = 10,
}) {
  // A raw platform-channel call that failed or returned early (e.g. the
  // native side had no interpreter loaded yet) comes back as an empty/short
  // list - bail out instead of indexing past the end of it.
  if (output.length < 5 * numAnchors) return const [];

  final ymin = <double>[];
  final xmin = <double>[];
  final ymax = <double>[];
  final xmax = <double>[];
  final scores = <double>[];

  for (int i = 0; i < numAnchors; i++) {
    final score = output[4 * numAnchors + i];
    if (score < confidenceThreshold) continue;

    final cx = output[0 * numAnchors + i];
    final cy = output[1 * numAnchors + i];
    final w = output[2 * numAnchors + i];
    final h = output[3 * numAnchors + i];

    ymin.add(cy - h / 2);
    xmin.add(cx - w / 2);
    ymax.add(cy + h / 2);
    xmax.add(cx + w / 2);
    scores.add(score);
  }

  final order = List<int>.generate(scores.length, (i) => i)
    ..sort((a, b) => scores[b].compareTo(scores[a]));

  final active = List<bool>.filled(scores.length, true);
  final selected = <int>[];
  for (int idx = 0; idx < order.length; idx++) {
    if (selected.length >= maxDetections) break;
    final i = order[idx];
    if (!active[i]) continue;
    selected.add(i);
    for (int jdx = idx + 1; jdx < order.length; jdx++) {
      final j = order[jdx];
      if (active[j] &&
          _iou(ymin[i], xmin[i], ymax[i], xmax[i], ymin[j], xmin[j], ymax[j],
                  xmax[j]) >
              nmsIouThreshold) {
        active[j] = false;
      }
    }
  }

  return [
    for (final i in selected)
      YoloDetection(
          ymin: ymin[i], xmin: xmin[i], ymax: ymax[i], xmax: xmax[i], score: scores[i])
  ];
}

/// Highest raw confidence score found in the output, regardless of
/// threshold - a diagnostic to tell "nothing detected because every score
/// is near zero" apart from "nothing detected because everything is just
/// under the confidence threshold".
double maxYoloScore(List<double> output, int numAnchors) {
  if (output.length < 5 * numAnchors) return 0.0;
  double best = 0.0;
  for (int i = 0; i < numAnchors; i++) {
    final s = output[4 * numAnchors + i];
    if (s > best) best = s;
  }
  return best;
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

/// Same shape ssdDetectionsToRecognitions produces (rect: {x,y,w,h},
/// detectedClass, confidenceInClass, inferenceTime, preProcessingTime) so
/// the app's existing rendering/alert code doesn't need to care which model
/// produced a detection.
List<Map<String, dynamic>> yoloDetectionsToRecognitions(
    List<YoloDetection> detections) {
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
        'inferenceTime': 0,
        'preProcessingTime': 0,
      }
  ];
}
