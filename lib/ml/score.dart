import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart' show rootBundle;
import 'inference.dart';
import 'indicators.dart';
import 'market.dart';

const features = [
  'rsi', 'dist_sma50', 'dist_sma200', 'dd_252', 'ret_5d', 'ret_20d',
  'range_pos_20', 'vol_ratio', 'vol_20d', 'atr_pct',
  'bull_div_5', 'bear_div_5', 'rsi_lt30', 'rsi_lt25',
];
const grid = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 12, 14, 16, 18, 20, 25, 30, 40, 50, 60, 80, 100, 120];

class ModelPair {
  HgbModel? reg;
  HgbModel? clf;
  double thr = 0;
}

final _modelCache = <String, ModelPair>{};

Future<ModelPair> loadModelPair(String tag, String key) async {
  final ck = '$tag/$key';
  if (_modelCache.containsKey(ck)) return _modelCache[ck]!;
  final p = ModelPair();
  p.reg = HgbModel.fromJson(await rootBundle.loadString('assets/models/${tag}_${key}_reg.json'), false);
  p.clf = HgbModel.fromJson(await rootBundle.loadString('assets/models/${tag}_${key}_clf.json'), true);
  final man = jsonDecode(await rootBundle.loadString('assets/models/manifest.json'));
  p.thr = ((man['models']?[tag]?[key]?['thr']) as num?)?.toDouble() ?? 0.0;
  _modelCache[ck] = p;
  return p;
}

class StockHist {
  final String ticker;
  final List<Candle> candles;
  late final List<double> close, high, low, volume, open;
  late final List<double> rsiV, sma50, sma200, dist50, dist200, dd, ret5, ret20,
      rangePos, volRatio, vol20, atrP, bull5, bear5;
  late final List<DivSignal> divs;
  late final double sma20last;

  StockHist(this.ticker, this.candles) {
    close = candles.map((c) => c.c).toList();
    high = candles.map((c) => c.h).toList();
    low = candles.map((c) => c.l).toList();
    volume = candles.map((c) => c.v).toList();
    open = candles.map((c) => c.o).toList();
    rsiV = rsi(close);
    sma50 = sma(close, 50);
    sma200 = sma(close, 200);
    final n = close.length;
    dist50 = List.generate(n, (i) => sma50[i].isNaN ? double.nan : close[i] / sma50[i] - 1);
    dist200 = List.generate(n, (i) => sma200[i].isNaN ? double.nan : close[i] / sma200[i] - 1);
    final rollMax252 = rollMax(close, 252, minP: 50);
    dd = List.generate(n, (i) => rollMax252[i].isNaN ? double.nan : close[i] / rollMax252[i] - 1);
    ret5 = List.generate(n, (i) => i < 5 || close[i - 5] == 0 ? double.nan : close[i] / close[i - 5] - 1);
    ret20 = List.generate(n, (i) => i < 20 || close[i - 20] == 0 ? double.nan : close[i] / close[i - 20] - 1);
    final lo20 = rollMin(low, 20), hi20 = rollMax(high, 20);
    rangePos = List.generate(n, (i) {
      if (lo20[i].isNaN || hi20[i].isNaN || (hi20[i] - lo20[i]) == 0) return double.nan;
      return (close[i] - lo20[i]) / (hi20[i] - lo20[i]);
    });
    final volMean = rollMean(volume, 20);
    volRatio = List.generate(n, (i) => volMean[i].isNaN || volMean[i] == 0 ? double.nan : volume[i] / volMean[i]);
    final ret1 = List.generate(n, (i) => i < 1 || close[i - 1] == 0 ? double.nan : close[i] / close[i - 1] - 1);
    vol20 = rollStd(ret1, 20);
    final a = atr(high, low, close);
    atrP = List.generate(n, (i) => a[i].isNaN ? double.nan : a[i] / close[i]);
    divs = detectDivergence(close, rsiV);
    final bullDays = <int>{}, bearDays = <int>{};
    for (final s in divs) {
      if (s.type == 'bullish') {
        bullDays.add(s.i1);
        bullDays.add(s.i2);
      } else {
        bearDays.add(s.i1);
        bearDays.add(s.i2);
      }
    }
    // flag = أي إشارة خلال آخر 5 جلسات (يقارب تواريخ date2 ± تحمّل)
    bull5 = List.generate(n, (i) {
      for (var k = 0; k < 5; k++) {
        if (bullDays.contains(i - k)) return 1.0;
      }
      return 0.0;
    });
    bear5 = List.generate(n, (i) {
      for (var k = 0; k < 5; k++) {
        if (bearDays.contains(i - k)) return 1.0;
      }
      return 0.0;
    });
    var s20 = 0.0;
    var cnt = 0;
    for (var i = n - 20; i < n; i++) {
      if (i >= 0) {
        s20 += close[i];
        cnt++;
      }
    }
    sma20last = cnt > 0 ? s20 / cnt : double.nan;
  }

  List<double> rowAt(int i) {
    return [
      rsiV[i], dist50[i], dist200[i], dd[i], ret5[i], ret20[i], rangePos[i],
      volRatio[i], vol20[i], atrP[i], bull5[i], bear5[i],
      rsiV[i] < 30 ? 1.0 : 0.0, rsiV[i] < 25 ? 1.0 : 0.0,
    ];
  }

  bool rowOk(int i) => !rowAt(i).any((v) => v.isNaN);
}

/// (n, wins) لصفوف مشابهة في تاريخ السهم لنفس المدة.
List<int> precedent(StockHist h, int? horizonDays) {
  final n = h.candles.length;
  final cur = h.rowAt(n - 1);
  var count = 0, wins = 0;
  for (var i = 0; i < n - 1; i++) {
    final r = h.rowAt(i);
    if (r.any((v) => v.isNaN)) continue;
    if ((r[0] - cur[0]).abs() > 5) continue;
    if ((r[4] - cur[4]).abs() > 0.04) continue;
    if ((r[6] - cur[6]).abs() > 0.20) continue;
    if ((r[3] - cur[3]).abs() > 0.06) continue;
    double? fwd;
    if (horizonDays == null) {
      if (i + 1 >= n) continue;
      if (h.open[i + 1] == 0) continue;
      fwd = h.close[i + 1] / h.open[i + 1] - 1;
    } else {
      if (i + horizonDays >= n) continue;
      if (h.close[i] == 0) continue;
      fwd = h.close[i + horizonDays] / h.close[i] - 1;
    }
    if (fwd.isNaN) continue;
    count++;
    if (fwd > 0) wins++;
  }
  return [count, wins];
}

String precStr(int n, int w) => n == 0 ? 'لا سوابق' : '$w/$n (${(w / n * 100).round()}%)';

String rsiRange(List<double> rsiV) {
  final t = rsiV.sublist(rsiV.length - 14 > 0 ? rsiV.length - 14 : 0);
  final lo = t.reduce((a, b) => a < b ? a : b);
  final hi = t.reduce((a, b) => a > b ? a : b);
  return '${lo.toStringAsFixed(1)} - ${hi.toStringAsFixed(1)}';
}

/// (decision, entry, entryExp)
List entryPlan(double close, double sma20, double rsiV, bool extended, double exp) {
  if (extended || rsiV >= 70 || (!sma20.isNaN && close > sma20 * 1.02)) {
    final tgt = double.parse((sma20.isNaN ? close * 0.95 : (sma20 > close * 0.95 ? sma20 : close * 0.95)).toStringAsFixed(2));
    if (tgt >= close) return ['دخول حالا', close.toStringAsFixed(2), exp.toStringAsFixed(2)];
    final p = close * (1 + exp / 100);
    return ['انتظار ${tgt.toStringAsFixed(2)}', tgt.toStringAsFixed(2), ((p - tgt) / tgt * 100).toStringAsFixed(2)];
  }
  return ['دخول حالا', close.toStringAsFixed(2), exp.toStringAsFixed(2)];
}

String reasonOf(Map<String, double> f) {
  final r = <String>[];
  if (f['extended'] == 1.0) r.add('ممتد - خطر مطاردة');
  if (f['rsi']! < 25) {
    r.add('RSI<25');
  } else if (f['rsi']! < 30) {
    r.add('RSI<30');
  }
  if (f['bull_div_5']! > 0) r.add('دايفرجنس صاعد قريب');
  if (f['dd_252']! <= -0.15) {
    r.add('هبوط>=15% من القمة');
  } else if (f['dd_252']! <= -0.10) {
    r.add('هبوط>=10% من القمة');
  }
  if (f['dist_sma50']! < 0) r.add('تحت متوسط50');
  if (f['vol_ratio']! > 1.5) r.add('سيولة عالية');
  if (r.isEmpty) r.add('زخم سعري');
  return r.join(' + ');
}

String fmt(double v, [int d = 2]) => v.isNaN ? '' : v.toStringAsFixed(d);
String fmt1(double v) => v.isNaN ? '' : v.toStringAsFixed(1);
