import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/io.dart';
import 'indicators.dart';

const _tvUrl = 'wss://data.tradingview.com/socket.io/websocket';
const _ua = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36';

bool _validCandle(double o, double h, double l, double c) {
  if (o <= 0 || h <= 0 || l <= 0 || c <= 0) return false;
  if (h < o || h < l || h < c) return false;
  if (l > o || l > h || l > c) return false;
  return true;
}

/// Yahoo Finance chart API (5y daily). Returns null on failure.
Future<List<Candle>?> fetchYahoo(String ticker) async {
  final sym = '$ticker.CA';
  final uri = Uri.parse('https://query1.finance.yahoo.com/v8/finance/chart/$sym?range=5y&interval=1d');
  try {
    final r = await http.get(uri, headers: {'User-Agent': _ua}).timeout(const Duration(seconds: 25));
    if (r.statusCode != 200) return null;
    final result = (jsonDecode(r.body)['chart']?['result'] as List?)?.firstOrNull;
    if (result == null) return null;
    final ts = (result['timestamp'] as List?)?.map((e) => (e as num).toInt()).toList() ?? [];
    final q = (result['indicators']?['quote'] as List?)?.firstOrNull;
    if (q == null || ts.isEmpty) return null;
    List<double?> col(String k) => (q[k] as List?)?.map((e) => e == null ? null : (e as num).toDouble()).toList() ?? [];
    final o = col('open'), h = col('high'), l = col('low'), c = col('close'), v = col('volume');
    final out = <Candle>[];
    for (var i = 0; i < ts.length; i++) {
      final oo = i < o.length ? o[i] : null;
      final hh = i < h.length ? h[i] : null;
      final ll = i < l.length ? l[i] : null;
      final cc = i < c.length ? c[i] : null;
      if (oo == null || hh == null || ll == null || cc == null) continue;
      if (!_validCandle(oo, hh, ll, cc)) continue;
      final vv = (i < v.length ? v[i] : null) ?? 0.0;
      out.add(Candle(
        date: DateTime.fromMillisecondsSinceEpoch(ts[i] * 1000, isUtc: true),
        o: oo, h: hh, l: ll, c: cc, v: vv < 0 ? 0.0 : vv,
      ));
    }
    return out.length >= 60 ? out : null;
  } catch (_) {
    return null;
  }
}

extension<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

String _fmt(Map<String, dynamic> p) {
  final enc = jsonEncode(p);
  return '~m~${enc.length}~m~$enc';
}

List<Map<String, dynamic>> _parseTv(String data) {
  final msgs = <Map<String, dynamic>>[];
  var cur = 0;
  while (true) {
    final s = data.indexOf('~m~', cur);
    if (s < 0) break;
    final ls = s + 3;
    final le = data.indexOf('~m~', ls);
    if (le < 0) break;
    final ln = int.tryParse(data.substring(ls, le));
    if (ln == null) {
      cur = le + 3;
      continue;
    }
    final ps = le + 3;
    if (ps + ln > data.length) break;
    final payload = data.substring(ps, ps + ln);
    cur = ps + ln;
    if (payload.startsWith('~h~')) continue;
    try {
      final dec = jsonDecode(payload);
      if (dec is Map<String, dynamic>) msgs.add(dec);
    } catch (_) {}
  }
  return msgs;
}

/// TradingView WebSocket history (fallback when Yahoo misses a ticker).
Future<List<Candle>?> fetchTradingView(String ticker, {int count = 1400}) async {
  IOWebSocketChannel? ch;
  try {
    final sym = 'EGX:$ticker';
    final channel = IOWebSocketChannel.connect(Uri.parse(_tvUrl),
        protocols: ['soap'], headers: {'Origin': 'https://www.tradingview.com', 'User-Agent': _ua});
    ch = channel;
    await channel.ready.timeout(const Duration(seconds: 15));
    final cs = 'cs_${DateTime.now().microsecondsSinceEpoch}';
    const series = 's1';
    final done = Completer<List<dynamic>>();
    final sub = channel.stream.listen((raw) {
      final r = raw.toString();
      if (r.startsWith('~h~')) {
        channel.sink.add(r);
        return;
      }
      for (final m in _parseTv(r)) {
        if (m['m'] == 'timescale_update') {
          final params = m['p'] as List?;
          if (params != null && params.length >= 2 && params[0] == cs) {
            final smap = params[1];
            if (smap is Map && smap[series] is Map) {
              final pts = (smap[series] as Map)['s'];
              if (pts is List && !done.isCompleted) done.complete(pts);
            }
          }
        }
      }
    }, onError: (e) {
      if (!done.isCompleted) done.completeError(e);
    });
    channel.sink.add(_fmt({'m': 'set_auth_token', 'p': ['unauthorized_user_token']}));
    channel.sink.add(_fmt({'m': 'chart_create_session', 'p': [cs, '']}));
    final res = jsonEncode({'symbol': sym, 'adjustment': 'splits'});
    channel.sink.add(_fmt({'m': 'resolve_symbol', 'p': [cs, 'symbol_1', '=$res']}));
    channel.sink.add(_fmt({'m': 'create_series', 'p': [cs, series, series, 'symbol_1', '1D', count]}));
    final pts = await done.future.timeout(const Duration(seconds: 25));
    await sub.cancel();
    final byTs = <int, Candle>{};
    for (final pt in pts) {
      final v = (pt is Map) ? pt['v'] : null;
      if (v is! List || v.length < 5) continue;
      try {
        final t = (v[0] as num).toInt();
        final oo = (v[1] as num).toDouble(), hh = (v[2] as num).toDouble();
        final ll = (v[3] as num).toDouble(), cc = (v[4] as num).toDouble();
        final vv = v.length > 5 && v[5] != null ? (v[5] as num).toDouble() : 0.0;
        if (!_validCandle(oo, hh, ll, cc)) continue;
        byTs[t] = Candle(
            date: DateTime.fromMillisecondsSinceEpoch(t * 1000, isUtc: true),
            o: oo, h: hh, l: ll, c: cc, v: vv < 0 ? 0 : vv);
      } catch (_) {}
    }
    final out = byTs.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
    final candles = out.map((e) => e.value).toList();
    return candles.length >= 60 ? candles : null;
  } catch (_) {
    return null;
  } finally {
    try {
      await ch?.sink.close();
    } catch (_) {}
  }
}

/// TradingView أولاً (متأخر ربع ساعة فقط) ثم Yahoo للفاشل (قد تتأخر أياماً).
/// Null if both fail.
Future<(List<Candle>?, String)> fetchTicker(String ticker) async {
  final t = await fetchTradingView(ticker);
  if (t != null) return (t, 'tradingview');
  final y = await fetchYahoo(ticker);
  if (y != null) return (y, 'yahoo');
  return (null, 'fail');
}

/// Full EGX universe from TradingView scanner (for refresh-all).
Future<List<String>> fetchUniverse() async {
  final uri = Uri.parse('https://scanner.tradingview.com/egypt/scan');
  final payload = {
    'filter': [
      {'left': 'type', 'operation': 'equal', 'right': 'stock'}
    ],
    'options': {'lang': 'ar'},
    'markets': ['egypt'],
    'symbols': {'query': {'types': []}, 'tickers': []},
    'columns': ['name'],
    'sort': {'sortBy': 'name', 'sortOrder': 'asc'},
    'range': [0, 1000],
  };
  final r = await http
      .post(uri,
          headers: {'Origin': 'https://www.tradingview.com', 'Referer': 'https://www.tradingview.com/', 'User-Agent': _ua, 'Content-Type': 'application/json'},
          body: jsonEncode(payload))
      .timeout(const Duration(seconds: 20));
  if (r.statusCode != 200) throw Exception('scanner ${r.statusCode}');
  final data = (jsonDecode(r.body)['data'] as List?) ?? [];
  final out = <String>{};
  final pat = RegExp(r'^[A-Z0-9]{1,24}$');
  final isin = RegExp(r'^EGS[A-Z0-9]{9,}$');
  for (final row in data) {
    final s = row['s']?.toString() ?? '';
    if (!s.contains(':')) continue;
    final parts = s.split(':');
    final t = parts[1].trim().toUpperCase();
    if (parts[0].trim().toUpperCase() == 'EGX' && pat.hasMatch(t) && !isin.hasMatch(t)) {
      out.add(t);
    }
  }
  return out.toList()..sort();
}
