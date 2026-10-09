import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as ppath;
import 'package:path_provider/path_provider.dart';
import 'market.dart';
import 'score.dart';

const _grid = grid;

Future<Directory> dataDir() async {
  final base = await getApplicationDocumentsDirectory();
  final d = Directory(ppath.join(base.path, 'mobile-data'));
  if (!await d.exists()) await d.create(recursive: true);
  return d;
}

String _s(double v, [int n = 2]) => v.isNaN ? '' : v.toStringAsFixed(n);

Map<String, String> _baseRow(StockHist h) {
  final i = h.candles.length - 1;
  final r = h.rowAt(i);
  final t = h.candles[i].date.toIso8601String().substring(0, 10);
  return {
    'ticker': h.ticker, 'date': t,
    'close': _s(h.close[i]), 'rsi': r[0].toString(),
    'rsi_range': rsiRange(h.rsiV),
    'rsi_lo14': '', 'rsi_hi14': '',
    'sma20': h.sma20last.isNaN ? '' : h.sma20last.toStringAsFixed(2),
    for (var k = 0; k < features.length; k++) features[k]: r[k].isNaN ? '' : r[k].toString(),
    'reason': '',
    'precedent': '',
  };
}

String _conf(double p) => p >= 60 ? 'قوية' : (p >= 50 ? 'متوسطة' : 'ضعيفة');

Future<void> _writeCsv(File f, List<String> header, List<Map<String, String>> rows) async {
  final sb = StringBuffer()..writeln(header.join(','));
  for (final r in rows) {
    sb.writeln(header.map((h) {
      var v = r[h] ?? '';
      if (v.contains(',') || v.contains('"')) v = '"${v.replaceAll('"', '""')}"';
      return v;
    }).join(','));
  }
  await f.writeAsString(sb.toString(), encoding: utf8);
}

List<Map<String, String>> _readCsvTable(String text) {
  final lines = text.split('\n').where((l) => l.trim().isNotEmpty).toList();
  if (lines.isEmpty) return [];
  // simple parse (our writer never emits commas inside except quoted reasons)
  List<String> split(String line) {
    final out = <String>[];
    var cur = StringBuffer();
    var q = false;
    for (var i = 0; i < line.length; i++) {
      final ch = line[i];
      if (q) {
        if (ch == '"') {
          if (i + 1 < line.length && line[i + 1] == '"') {
            cur.write('"');
            i++;
          } else {
            q = false;
          }
        } else {
          cur.write(ch);
        }
      } else if (ch == '"') {
        q = true;
      } else if (ch == ',') {
        out.add(cur.toString());
        cur = StringBuffer();
      } else {
        cur.write(ch);
      }
    }
    out.add(cur.toString());
    return out;
  }

  final head = split(lines.first);
  return lines.skip(1).map((l) {
    final cells = split(l);
    return {for (var i = 0; i < head.length; i++) head[i]: i < cells.length ? cells[i] : ''};
  }).toList();
}

class RefreshReport {
  int ok = 0, fail = 0;
  String asof = '';
  int consensus = 0;
  List<String> failedTickers = [];
}

/// Full on-device refresh for one universe. Calls onProgress(done, total, ticker).
Future<RefreshReport> refreshUniverse(
  String tag, {
  required Future<void> Function(int done, int total, String ticker) onProgress,
}) async {
  final rep = RefreshReport();
  // tickers: ALL -> live scanner, EGX33 -> bundled fixed set
  List<String> tickers;
  if (tag == 'all') {
    try {
      tickers = await fetchUniverse();
    } catch (_) {
      tickers = [];
    }
    if (tickers.isEmpty) {
      final raw = await rootBundle.loadString('assets/data/all_scores.csv');
      tickers = _readCsvTable(raw).map((r) => r['ticker']!).toSet().toList();
    }
  } else {
    final raw = await rootBundle.loadString('assets/data/egx33_scores.csv');
    tickers = _readCsvTable(raw).map((r) => r['ticker']!).toSet().toList();
  }

  final hists = <String, StockHist>{};
  var done = 0;
  for (var i = 0; i < tickers.length; i += 6) {
    final chunk = tickers.sublist(i, (i + 6 > tickers.length) ? tickers.length : i + 6);
    final res = await Future.wait(chunk.map((t) async {
      final r = await fetchTicker(t);
      done++;
      await onProgress(done, tickers.length, t);
      return MapEntry(t, r);
    }));
    for (final e in res) {
      final c = e.value.$1;
      if (c != null && c.length >= 60) {
        final h = StockHist(e.key, c);
        if (h.rowOk(h.candles.length - 1)) {
          hists[e.key] = h;
          rep.ok++;
        } else {
          rep.fail++;
          rep.failedTickers.add(e.key);
        }
      } else {
        rep.fail++;
        rep.failedTickers.add(e.key);
      }
    }
  }
  if (hists.isEmpty) throw Exception('no data fetched');

  // breadth regime
  var above = 0;
  hists.forEach((_, h) {
    final i = h.candles.length - 1;
    if (!h.sma50[i].isNaN && h.close[i] > h.sma50[i]) above++;
  });
  final regime = above / hists.length >= 0.5;

  // models
  final intra = await loadModelPair(tag, 'intra');
  final gridModels = <int, ModelPair>{};
  for (final h in _grid) {
    gridModels[h] = await loadModelPair(tag, 'h$h');
  }
  final otherTag = tag == 'egx33' ? 'all' : 'egx33';
  final otherH5 = await loadModelPair(otherTag, 'h5');

  // score
  final names = hists.keys.toList();
  final featRows = names.map((t) => hists[t]!.rowAt(hists[t]!.candles.length - 1)).toList();
  List<double> expOf(ModelPair m) => [for (final x in featRows) m.reg!.predictReg(x) * 100];
  List<double> probOf(ModelPair m) => [for (final x in featRows) m.clf!.predictProba(x) * 100];
  final iExp = expOf(intra), iProb = probOf(intra);
  final gExp = <int, List<double>>{}, gProb = <int, List<double>>{};
  for (final h in _grid) {
    gExp[h] = expOf(gridModels[h]!);
    gProb[h] = probOf(gridModels[h]!);
  }
  final oExp = [for (final x in featRows) otherH5.reg!.predictReg(x) * 100];
  final oProb = [for (final x in featRows) otherH5.clf!.predictProba(x) * 100];

  final rows = <Map<String, String>>[];
  for (var k = 0; k < names.length; k++) {
    final h = hists[names[k]]!;
    final r = _baseRow(h);
    r['intra_exp'] = _s(iExp[k]);
    r['intra_p'] = _s(iProb[k], 1);
    r['intra_conf'] = _conf(iProb[k]);
    for (final hh in _grid) {
      r['h${hh}_exp'] = _s(gExp[hh]![k]);
      r['h${hh}_p'] = _s(gProb[hh]![k], 1);
    }
    // best swing {5,10,20} / invest {60,120}
    List best(List<int> hs) {
      var bi = hs.first;
      for (final hh in hs) {
        final useProb = gProb[hh]![k] > 50;
        final curUse = gProb[bi]![k] > 50;
        if ((useProb && !curUse) || (useProb == curUse && gExp[hh]![k] > gExp[bi]![k])) bi = hh;
      }
      return [bi, gExp[bi]![k], gProb[bi]![k]];
    }

    final sb = best([5, 10, 20]), ib = best([60, 120]);
    r['swing_best_h'] = '${sb[0]}';
    r['swing_best_exp'] = _s(sb[1]);
    r['swing_best_p'] = _s(sb[2], 1);
    r['swing_best_conf'] = _conf(sb[2]);
    r['inv_best_h'] = '${ib[0]}';
    r['inv_best_exp'] = _s(ib[1]);
    r['inv_best_p'] = _s(ib[2], 1);
    r['inv_best_conf'] = _conf(ib[2]);
    r['sw5_exp'] = _s(gExp[5]![k]);
    r['sw5_p'] = _s(gProb[5]![k], 1);
    r['sw5_conf'] = _conf(gProb[5]![k]);
    r['o5_exp'] = _s(oExp[k]);
    r['o5_p'] = _s(oProb[k], 1);
    final fmap = {for (var j = 0; j < features.length; j++) features[j]: featRows[k][j]};
    final ext = (fmap['ret_5d']! > 0.10) || (fmap['range_pos_20']! >= 0.95);
    r['extended'] = ext ? 'True' : 'False';
    r['reason'] = reasonOf({...fmap, 'extended': ext ? 1.0 : 0.0});
    // entry plans
    List ep(double e) => entryPlan(
        h.close.last, h.sma20last, fmap['rsi']!, ext, e);
    var a = ep(iExp[k]);
    r['in_dec'] = a[0] as String;
    r['in_entry'] = a[1] as String;
    r['in_entry_exp'] = a[2] as String;
    a = ep(sb[1] as double);
    r['sw_dec'] = a[0] as String;
    r['sw_entry'] = a[1] as String;
    r['sw_entry_exp'] = a[2] as String;
    a = ep(gExp[5]![k]);
    r['s5_dec'] = a[0] as String;
    r['s5_entry'] = a[1] as String;
    r['s5_entry_exp'] = a[2] as String;
    a = ep(ib[1] as double);
    r['iv_dec'] = a[0] as String;
    r['iv_entry'] = a[1] as String;
    r['iv_entry_exp'] = a[2] as String;
    rows.add(r);
  }

  String prec(int k, int? h) {
    final t = names[k];
    final p = precedent(hists[t]!, h);
    return precStr(p[0], p[1]);
  }

  List<Map<String, String>> top(String expKey, {bool skipExtended = true}) {
    final idx = [for (var k = 0; k < rows.length; k++) k]
        .where((k) => !(skipExtended && rows[k]['extended'] == 'True'))
        .toList()
      ..sort((a, b) => (double.tryParse(rows[b][expKey] ?? '') ?? -1e18)
          .compareTo(double.tryParse(rows[a][expKey] ?? '') ?? -1e18));
    return idx.take(8).map((k) => rows[k]).toList();
  }

  final picks = {
    'intraday': top('intra_exp'),
    'swing': top('swing_best_exp'),
    'swing5': top('sw5_exp'),
    'invest': top('inv_best_exp'),
    'excluded': rows.where((r) => r['extended'] == 'True').toList()
      ..sort((a, b) => (double.tryParse(b['swing_best_exp'] ?? '') ?? -1e18)
          .compareTo(double.tryParse(a['swing_best_exp'] ?? '') ?? -1e18)),
  };
  for (final e in picks['intraday']!) {
    e['precedent'] = prec(names.indexOf(e['ticker']!), null);
  }
  for (final e in picks['swing']!) {
    e['precedent'] = prec(names.indexOf(e['ticker']!), int.parse(e['swing_best_h']!));
  }
  for (final e in picks['swing5']!) {
    e['precedent'] = prec(names.indexOf(e['ticker']!), 5);
  }
  for (final e in picks['invest']!) {
    e['precedent'] = prec(names.indexOf(e['ticker']!), int.parse(e['inv_best_h']!));
  }
  for (final e in picks['excluded']!) {
    e['precedent'] = prec(names.indexOf(e['ticker']!), int.parse(e['swing_best_h']!));
  }
  // consensus
  final cons = rows.where((r) {
    final k = names.indexOf(r['ticker']!);
    if (r['extended'] == 'True') return false;
    if ((double.tryParse(r['rsi'] ?? '') ?? 99) >= 35) return false;
    if ((double.tryParse(r['h5_exp'] ?? '') ?? 0) <= 0 || oExp[k] <= 0) return false;
    if ((double.tryParse(r['h5_p'] ?? '') ?? 0) < 60 || oProb[k] < 60) return false;
    if (!regime) return false;
    final p = precedent(hists[r['ticker']!]!, 5);
    return p[0] >= 4 && p[1] / p[0] >= 0.75;
  }).toList()
    ..sort((a, b) => (double.tryParse(b['h5_exp'] ?? '') ?? -1e18)
        .compareTo(double.tryParse(a['h5_exp'] ?? '') ?? -1e18));
  final consTop = cons.take(8).toList();
  for (final e in consTop) {
    e['precedent'] = prec(names.indexOf(e['ticker']!), 5);
  }
  rep.consensus = consTop.length;

  // customs
  final customs = <int, List<Map<String, String>>>{};
  for (final h in _grid) {
    final idx = [for (var k = 0; k < rows.length; k++) k]
        .where((k) => rows[k]['extended'] != 'True')
        .toList()
      ..sort((a, b) => (double.tryParse(rows[b]['h${h}_exp'] ?? '') ?? -1e18)
          .compareTo(double.tryParse(rows[a]['h${h}_exp'] ?? '') ?? -1e18));
    final lst = idx.take(8).map((k) {
      final r = Map<String, String>.from(rows[k]);
      final hh = hists[r['ticker']!]!;
      r['ch_h'] = '$h';
      r['ch_exp'] = r['h${h}_exp']!;
      r['ch_p'] = r['h${h}_p']!;
      r['ch_conf'] = _conf(double.tryParse(r['ch_p']!) ?? 0);
      final a2 = entryPlan(double.tryParse(r['close']!) ?? 0, hh.sma20last,
          double.tryParse(r['rsi']!) ?? 99, false, double.tryParse(r['ch_exp']!) ?? 0);
      r['ch_dec'] = a2[0] as String;
      r['ch_entry'] = a2[1] as String;
      r['ch_entry_exp'] = a2[2] as String;
      r['precedent'] = prec(k, h);
      return r;
    }).toList();
    customs[h] = lst;
  }

  // all_scores precedents
  for (var k = 0; k < rows.length; k++) {
    rows[k]['prec_intra'] = prec(k, null);
    for (final h in _grid) {
      rows[k]['prec_$h'] = prec(k, h);
    }
  }

  // save
  final dir = await dataDir();
  final allDates = rows.map((r) => r['date']!).toList()..sort();
  final asof = allDates.last.replaceAll('-', '');
  rep.asof = asof;
  final allCols = rows.first.keys.toList();
  for (final e in picks.entries) {
    await _writeCsv(File(ppath.join(dir.path, '${tag}_${e.key}.csv')), allCols, e.value);
  }
  await _writeCsv(File(ppath.join(dir.path, '${tag}_consensus.csv')), allCols, consTop);
  for (final h in _grid) {
    await _writeCsv(
        File(ppath.join(dir.path, '${tag}_custom_$h.csv')),
        ['ticker', 'close', 'rsi', 'rsi_range', 'ch_h', 'ch_exp', 'ch_p', 'ch_conf', 'ch_dec', 'ch_entry', 'ch_entry_exp', 'precedent', 'reason'],
        customs[h]!);
  }
  await _writeCsv(
      File(ppath.join(dir.path, '${tag}_scores.csv')),
      ['ticker', 'date', 'close', 'rsi', 'rsi_range', 'sma20', 'extended', 'reason', 'intra_exp', 'intra_p',
       for (final h in _grid) ...['h${h}_exp', 'h${h}_p'], 'prec_intra', for (final h in _grid) 'prec_$h'],
      rows);

  // trades log: seed from bundle, append new, settle
  final logF = File(ppath.join(dir.path, '${tag}_trades.csv'));
  List<Map<String, String>> log;
  if (await logF.exists()) {
    log = _readCsvTable(await logF.readAsString());
  } else {
    try {
      log = _readCsvTable(await rootBundle.loadString('assets/data/${tag}_trades.csv'));
    } catch (_) {
      log = [];
    }
  }
  bool dup(String l, String t, String d) => log.any((r) => r['source'] == 'موبايل' && r['list'] == l && r['ticker'] == t && r['entry_date'] == d);
  final today = rows.first['date']!;
  void addTr(List<Map<String, String>> lst, String l, int Function(Map<String, String>) hz, String Function(Map<String, String>) ex, String Function(Map<String, String>) pr) {
    for (final r in lst) {
      if (dup(l, r['ticker']!, today)) continue;
      log.add({'source': 'موبايل', 'list': l, 'ticker': r['ticker']!, 'entry_date': today, 'entry_price': r['close']!,
               'horizon': '${hz(r)}', 'exit_date': '', 'pred_pct': ex(r), 'prob': pr(r), 'actual_pct': '', 'result': 'معلقة'});
    }
  }

  addTr(picks['intraday']!, 'انتراداي', (_) => 1, (r) => r['intra_exp']!, (r) => r['intra_p']!);
  addTr(picks['swing']!, 'مضاربة', (r) => int.parse(r['swing_best_h']!), (r) => r['swing_best_exp']!, (r) => r['swing_best_p']!);
  addTr(picks['swing5']!, 'مضاربة (5 أيام)', (_) => 5, (r) => r['sw5_exp']!, (r) => r['sw5_p']!);
  addTr(consTop, 'إجماع', (_) => 5, (r) => r['h5_exp']!, (r) => r['h5_p']!);
  addTr(picks['invest']!, 'استثمار', (r) => int.parse(r['inv_best_h']!), (r) => r['inv_best_exp']!, (r) => r['inv_best_p']!);
  // settle
  final dates = <String, List<String>>{};
  hists.forEach((t, h) {
    dates[t] = h.candles.map((c) => c.date.toIso8601String().substring(0, 10)).toList();
  });
  double? closeAt(String t, String d) {
    final h = hists[t];
    if (h == null) return null;
    final i = dates[t]!.indexOf(d);
    return i < 0 ? null : h.close[i];
  }

  for (final r in log) {
    if (r['result'] != 'معلقة') continue;
    final t = r['ticker']!;
    final dl = dates[t];
    if (dl == null || !dl.contains(r['entry_date'])) continue;
    if (r['list'] == 'انتراداي') {
      final j = dl.indexOf(r['entry_date']!) + 1;
      if (j >= dl.length) continue;
      final h = hists[t]!;
      final act = (h.close[j] / h.open[j] - 1) * 100;
      r['entry_price'] = h.open[j].toStringAsFixed(2);
      r['exit_date'] = dl[j];
      r['actual_pct'] = act.toStringAsFixed(2);
      r['result'] = act > 0 ? 'كسبانة' : 'خسرانة';
    } else {
      final j = dl.indexOf(r['entry_date']!) + int.parse(r['horizon'] ?? '0');
      if (j >= dl.length) continue;
      final ex = closeAt(t, dl[j]);
      final en = double.tryParse(r['entry_price'] ?? '');
      if (ex == null || en == null || en == 0) continue;
      final act = (ex / en - 1) * 100;
      r['exit_date'] = dl[j];
      r['actual_pct'] = act.toStringAsFixed(2);
      r['result'] = act > 0 ? 'كسبانة' : 'خسرانة';
    }
  }
  await _writeCsv(
      logF,
      ['source', 'list', 'ticker', 'entry_date', 'entry_price', 'horizon', 'exit_date', 'pred_pct', 'prob', 'actual_pct', 'result'],
      log);
  final metaF = File(ppath.join(dir.path, 'meta.json'));
  Map<String, dynamic> meta = {};
  try {
    if (await metaF.exists()) {
      meta = Map<String, dynamic>.from(jsonDecode(await metaF.readAsString()));
    }
  } catch (_) {}
  try {
    final bundled = jsonDecode(await rootBundle.loadString('assets/data/meta.json')) as Map<String, dynamic>;
    for (final k in bundled.keys) {
      meta.putIfAbsent(k, () => bundled[k]);
    }
  } catch (_) {}
  meta[tag] = {'asof': asof};
  await metaF.writeAsString(jsonEncode(meta), encoding: utf8);
  return rep;
}
