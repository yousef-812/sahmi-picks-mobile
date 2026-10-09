import 'dart:convert';
import 'dart:math';

/// Exact port of sklearn HistGradientBoosting raw-split trees.
/// Node layout: [value, feature_idx, threshold, missing_go_to_left, left, right, is_leaf]
class HgbModel {
  final double baseline;
  final List<List<List<double>>> trees;
  final bool isClassifier;

  HgbModel({required this.baseline, required this.trees, required this.isClassifier});

  factory HgbModel.fromJson(String raw, bool isClassifier) {
    final m = jsonDecode(raw) as Map<String, dynamic>;
    final trees = (m['t'] as List)
        .map((tr) => (tr as List).map((n) => (n as List).map((v) => (v as num).toDouble()).toList()).toList())
        .toList();
    return HgbModel(
      baseline: (m['b'] as num).toDouble(),
      trees: trees,
      isClassifier: isClassifier,
    );
  }

  double _walk(List<List<double>> tree, List<double> x) {
    var n = 0;
    while (true) {
      final node = tree[n];
      if (node[6] == 1.0) return node[0];
      final f = node[1].toInt();
      final v = x[f];
      if (v.isNaN) {
        n = node[3] == 1.0 ? node[4].toInt() : node[5].toInt();
      } else {
        n = v <= node[2] ? node[4].toInt() : node[5].toInt();
      }
    }
  }

  /// Returns expected value (reg) or probability (clf).
  double predictRow(List<double> x, {required double Function(double) post}) {
    var s = baseline;
    for (final t in trees) {
      s += _walk(t, x);
    }
    return post(s);
  }

  double predictReg(List<double> x) => predictRow(x, post: (s) => s);

  double predictProba(List<double> x) => predictRow(x, post: (s) => 1.0 / (1.0 + exp(-s)));
}
