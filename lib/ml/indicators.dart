import 'dart:math';

/// Exact ports of the Python indicator math (pandas semantics).
class Candle {
  final DateTime date;
  final double o, h, l, c, v;
  Candle({required this.date, required this.o, required this.h, required this.l, required this.c, required this.v});
}

List<double> _ewm(List<double> x, double alpha, int minPeriods) {
  final out = List<double>.filled(x.length, double.nan);
  double? ema;
  var count = 0;
  for (var i = 0; i < x.length; i++) {
    if (x[i].isNaN) {
      out[i] = double.nan;
      continue;
    }
    count++;
    ema = ema == null ? x[i] : alpha * x[i] + (1 - alpha) * ema;
    out[i] = count >= minPeriods ? ema : double.nan;
  }
  return out;
}

/// RSI matching Python exactly (avg_loss 0 -> NaN -> fillna 50).
List<double> rsi(List<double> close, [int window = 14]) {
  // Python: rs = avg_gain / avg_loss.replace(0.0, nan); values = 100 - 100/(1+rs); fillna(50)
  final delta = List<double>.filled(close.length, double.nan);
  for (var i = 1; i < close.length; i++) {
    delta[i] = close[i] - close[i - 1];
  }
  final gains = delta.map((d) => d.isNaN ? double.nan : max(d, 0.0)).toList();
  final losses = delta.map((d) => d.isNaN ? double.nan : max(-d, 0.0)).toList();
  final ag = _ewm(gains, 1.0 / window, window);
  final al = _ewm(losses, 1.0 / window, window);
  return List.generate(close.length, (i) {
    if (ag[i].isNaN || al[i].isNaN) return 50.0;
    final denom = al[i] == 0.0 ? double.nan : al[i];
    if (denom.isNaN) return 50.0;
    final v = 100.0 - 100.0 / (1.0 + ag[i] / denom);
    return v.isNaN ? 50.0 : v;
  });
}

List<double> atr(List<double> h, List<double> l, List<double> c, [int window = 14]) {
  final tr = List<double>.filled(c.length, double.nan);
  for (var i = 0; i < c.length; i++) {
    if (i == 0) {
      tr[i] = h[i] - l[i];
    } else {
      tr[i] = max(h[i] - l[i], max((h[i] - c[i - 1]).abs(), (l[i] - c[i - 1]).abs()));
    }
  }
  return _ewm(tr, 1.0 / window, window);
}

List<double> sma(List<double> x, int n) {
  return List.generate(x.length, (i) {
    if (i + 1 < n) return double.nan;
    var s = 0.0;
    for (var k = i - n + 1; k <= i; k++) {
      if (x[k].isNaN) return double.nan;
      s += x[k];
    }
    return s / n;
  });
}

List<double> rollMax(List<double> x, int n, {int minP = 0}) {
  final mp = minP == 0 ? n : minP;
  return List.generate(x.length, (i) {
    if (i + 1 < mp) return double.nan;
    var m = double.negativeInfinity;
    for (var k = max(0, i - n + 1); k <= i; k++) {
      if (x[k].isNaN) return double.nan;
      if (x[k] > m) m = x[k];
    }
    return m;
  });
}

List<double> rollMin(List<double> x, int n, {int minP = 0}) {
  final mp = minP == 0 ? n : minP;
  return List.generate(x.length, (i) {
    if (i + 1 < mp) return double.nan;
    var m = double.infinity;
    for (var k = max(0, i - n + 1); k <= i; k++) {
      if (x[k].isNaN) return double.nan;
      if (x[k] < m) m = x[k];
    }
    return m;
  });
}

List<double> rollMean(List<double> x, int n) {
  return List.generate(x.length, (i) {
    if (i + 1 < n) return double.nan;
    var s = 0.0;
    for (var k = i - n + 1; k <= i; k++) {
      if (x[k].isNaN) return double.nan;
      s += x[k];
    }
    return s / n;
  });
}

/// Sample std (ddof=1) like pandas.
List<double> rollStd(List<double> x, int n) {
  return List.generate(x.length, (i) {
    if (i + 1 < n) return double.nan;
    var s = 0.0, s2 = 0.0;
    for (var k = i - n + 1; k <= i; k++) {
      if (x[k].isNaN) return double.nan;
      s += x[k];
      s2 += x[k] * x[k];
    }
    final v = (s2 - s * s / n) / (n - 1);
    return sqrt(max(v, 0.0));
  });
}

class DivSignal {
  final String type;
  final int i1, i2;
  DivSignal(this.type, this.i1, this.i2);
}

List<int> _pivots(List<double> v, int order, bool highs) {
  final out = <int>[];
  for (var i = order; i < v.length - order; i++) {
    if (v[i].isNaN) continue;
    var ok = true;
    for (var k = i - order; k <= i + order; k++) {
      if (k == i || v[k].isNaN) continue;
      if (highs ? v[k] > v[i] : v[k] < v[i]) {
        ok = false;
        break;
      }
    }
    if (!ok) continue;
    for (var k = i - order; k < i; k++) {
      if (v[k].isNaN) continue;
      if (highs ? !(v[i] > v[k]) : !(v[i] < v[k])) {
        ok = false;
        break;
      }
    }
    if (!ok) continue;
    for (var k = i + 1; k <= i + order; k++) {
      if (v[k].isNaN) continue;
      if (highs ? !(v[i] > v[k]) : !(v[i] < v[k])) {
        ok = false;
        break;
      }
    }
    if (ok) out.add(i);
  }
  return out;
}

int? _nearest(int idx, List<int> pivots, [int tol = 8]) {
  int? best;
  for (final r in pivots) {
    if ((r - idx).abs() <= tol && (best == null || (r - idx).abs() < (best - idx).abs())) {
      best = r;
    }
  }
  return best;
}

/// Regular bullish/bearish RSI divergence (same rules as Python).
List<DivSignal> detectDivergence(List<double> close, List<double> rsiV,
    {int order = 5, int tol = 8, int maxGap = 120}) {
  final out = <DivSignal>[];
  final pLows = _pivots(close, order, false);
  final rLows = _pivots(rsiV, order, false);
  final pHighs = _pivots(close, order, true);
  final rHighs = _pivots(rsiV, order, true);
  for (var j = 1; j < pLows.length; j++) {
    final i1 = pLows[j - 1], i2 = pLows[j];
    if (i2 - i1 > maxGap) continue;
    final r1 = _nearest(i1, rLows, tol), r2 = _nearest(i2, rLows, tol);
    if (r1 == null || r2 == null) continue;
    if (close[i2] < close[i1] && rsiV[r2] > rsiV[r1]) {
      out.add(DivSignal('bullish', i1, i2));
    }
  }
  for (var j = 1; j < pHighs.length; j++) {
    final i1 = pHighs[j - 1], i2 = pHighs[j];
    if (i2 - i1 > maxGap) continue;
    final r1 = _nearest(i1, rHighs, tol), r2 = _nearest(i2, rHighs, tol);
    if (r1 == null || r2 == null) continue;
    if (close[i2] > close[i1] && rsiV[r2] < rsiV[r1]) {
      out.add(DivSignal('bearish', i1, i2));
    }
  }
  return out;
}
