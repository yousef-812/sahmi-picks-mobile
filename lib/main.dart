import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:csv/csv.dart';
import 'dart:convert';

void main() => runApp(const PicksApp());

const navy = Color(0xFF1F4E78);
const gridH = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 12, 14, 16, 18, 20, 25, 30, 40, 50, 60, 80, 100, 120];

const listTitles = {
  'intraday': 'انتراداي (بيع آخر اليوم)',
  'swing': 'مضاربة',
  'swing5': 'مضاربة 5 أيام',
  'invest': 'استثمار',
  'consensus': 'صفقات الإجماع',
  'excluded': 'مستبعد (ممتد)',
};

const listFields = {
  'intraday': [
    ['close', 'السعر'], ['rsi', 'RSI'], ['rsi_range', 'مدى RSI'],
    ['intra_exp', 'المتوقع %'], ['intra_p', 'الاحتمال %'], ['intra_conf', 'الثقة'],
    ['in_dec', 'القرار'], ['in_entry', 'سعر الدخول'], ['in_entry_exp', 'المتوقع من الدخول %'],
    ['precedent', 'السوابق'], ['reason', 'السبب'],
  ],
  'swing': [
    ['close', 'السعر'], ['rsi', 'RSI'], ['rsi_range', 'مدى RSI'],
    ['swing_best_h', 'المدة (يوم)'], ['swing_best_exp', 'المتوقع %'],
    ['swing_best_p', 'الاحتمال %'], ['swing_best_conf', 'الثقة'],
    ['sw_dec', 'القرار'], ['sw_entry', 'سعر الدخول'], ['sw_entry_exp', 'المتوقع من الدخول %'],
    ['precedent', 'السوابق'], ['reason', 'السبب'],
  ],
  'swing5': [
    ['close', 'السعر'], ['rsi', 'RSI'], ['rsi_range', 'مدى RSI'],
    ['sw5_exp', 'المتوقع %'], ['sw5_p', 'الاحتمال %'], ['sw5_conf', 'الثقة'],
    ['s5_dec', 'القرار'], ['s5_entry', 'سعر الدخول'], ['s5_entry_exp', 'المتوقع من الدخول %'],
    ['precedent', 'السوابق'], ['reason', 'السبب'],
  ],
  'invest': [
    ['close', 'السعر'], ['rsi', 'RSI'], ['rsi_range', 'مدى RSI'],
    ['inv_best_h', 'المدة (يوم)'], ['inv_best_exp', 'المتوقع %'],
    ['inv_best_p', 'الاحتمال %'], ['inv_best_conf', 'الثقة'],
    ['iv_dec', 'القرار'], ['iv_entry', 'سعر الدخول'], ['iv_entry_exp', 'المتوقع من الدخول %'],
    ['precedent', 'السوابق'], ['reason', 'السبب'],
  ],
  'consensus': [
    ['close', 'السعر'], ['rsi', 'RSI'], ['rsi_range', 'مدى RSI'],
    ['sw5_exp', 'المتوقع %'], ['o5_exp', 'متوقع الكل %'], ['sw5_conf', 'الثقة'],
    ['s5_dec', 'القرار'], ['s5_entry', 'سعر الدخول'], ['s5_entry_exp', 'المتوقع من الدخول %'],
    ['precedent', 'السوابق'], ['reason', 'السبب'],
  ],
  'excluded': [
    ['close', 'السعر'], ['rsi', 'RSI'], ['rsi_range', 'مدى RSI'],
    ['swing_best_exp', 'المتوقع %'],
    ['sw_dec', 'القرار'], ['sw_entry', 'سعر الدخول'], ['sw_entry_exp', 'المتوقع من الدخول %'],
    ['precedent', 'السوابق'], ['reason', 'السبب'],
  ],
  'custom': [
    ['close', 'السعر'], ['rsi', 'RSI'], ['rsi_range', 'مدى RSI'],
    ['ch_exp', 'المتوقع %'], ['ch_p', 'الاحتمال %'], ['ch_conf', 'الثقة'],
    ['ch_dec', 'القرار'], ['ch_entry', 'سعر الدخول'], ['ch_entry_exp', 'المتوقع من الدخول %'],
    ['precedent', 'السوابق'], ['reason', 'السبب'],
  ],
  'search': [
    ['close', 'السعر الحالي'], ['rsi', 'RSI الحالي'], ['rsi_range', 'مدى RSI (14 يوم)'],
    ['h', 'المدة'], ['exp', 'العائد المتوقع %'], ['target', 'السعر المتوقع'],
    ['dec', 'القرار'], ['entry', 'سعر الدخول المقترح'], ['eentry', 'المتوقع من الدخول %'],
    ['prob', 'احتمال المكسب %'], ['conf', 'الثقة'], ['prec', 'السوابق'],
    ['state', 'الحالة'], ['reason', 'السبب'],
  ],
};

Future<List<Map<String, String>>> loadCsv(String path) async {
  try {
    final raw = await rootBundle.loadString(path);
    final rows = const CsvToListConverter().convert(raw);
    if (rows.isEmpty) return [];
    final head = rows.first.map((e) => e.toString()).toList();
    return rows.skip(1).map((r) {
      final m = <String, String>{};
      for (var i = 0; i < head.length && i < r.length; i++) {
        m[head[i]] = r[i].toString();
      }
      return m;
    }).toList();
  } catch (_) {
    return [];
  }
}

Color confColor(String? c) {
  if (c == 'قوية') return Colors.green.shade700;
  if (c == 'متوسطة') return Colors.amber.shade800;
  if (c == 'ضعيفة') return Colors.red.shade700;
  if (c == 'كسبانة') return Colors.green.shade700;
  if (c == 'خسرانة') return Colors.red.shade700;
  return Colors.grey.shade600;
}

class PicksApp extends StatelessWidget {
  const PicksApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'قوايم الأسهم',
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(colorSchemeSeed: navy, useMaterial3: true),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String universe = 'egx33';
  int tab = 0;
  String listKey = 'swing';
  int customH = 7;
  bool loading = true;
  String asof = '';
  Map<String, List<Map<String, String>>> lists = {};
  List<Map<String, String>> scores = [];
  List<Map<String, String>> trades = [];
  List<Map<String, String>> customRows = [];
  String searchTicker = '';
  String searchH = '5';
  Map<String, String>? searchResult;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => loading = true);
    final u = universe;
    final l = <String, List<Map<String, String>>>{};
    for (final k in ['intraday', 'swing', 'swing5', 'invest', 'consensus', 'excluded']) {
      l[k] = await loadCsv('assets/data/${u}_$k.csv');
    }
    final sc = await loadCsv('assets/data/${u}_scores.csv');
    final tr = await loadCsv('assets/data/${u}_trades.csv');
    String asofV = '';
    try {
      final metaStr = await rootBundle.loadString('assets/data/meta.json');
      final meta = jsonDecode(metaStr) as Map<String, dynamic>;
      final um = meta[u] as Map<String, dynamic>?;
      if (um != null && um['asof'] != null) asofV = um['asof'].toString();
    } catch (_) {}
    final cu = await loadCsv('assets/data/${u}_custom_$customH.csv');
    if (!mounted) return;
    setState(() {
      lists = l;
      scores = sc;
      trades = tr;
      asof = asofV;
      customRows = cu;
      searchResult = null;
      loading = false;
    });
  }

  Future<void> _loadCustom() async {
    final cu = await loadCsv('assets/data/${universe}_custom_$customH.csv');
    if (!mounted) return;
    setState(() => customRows = cu);
  }

  String? _confOf(Map<String, String> r, String key) {
    for (final f in (listFields[key] ?? const [])) {
      if (f[0].endsWith('_conf') || f[0] == 'conf') {
        final v = (r[f[0]] ?? '').trim();
        if (v.isNotEmpty) return v;
      }
    }
    return null;
  }

  Widget _card(Map<String, String> r, String key) {
    final fields = listFields[key] ?? const [];
    final conf = _confOf(r, key);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(r['ticker'] ?? '', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const Spacer(),
                if (conf != null)
                  Chip(
                    label: Text(conf, style: const TextStyle(color: Colors.white, fontSize: 12)),
                    backgroundColor: confColor(conf),
                    padding: EdgeInsets.zero,
                  ),
              ],
            ),
            const SizedBox(height: 4),
            for (final f in fields)
              if ((r[f[0]] ?? '').isNotEmpty && f[0] != 'ticker')
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 1.5),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(width: 130, child: Text('${f[1]}:', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
                      Expanded(child: Text(r[f[0]]!, style: const TextStyle(fontSize: 13))),
                    ],
                  ),
                ),
          ],
        ),
      ),
    );
  }

  Widget _listsTab() {
    final rows = listKey == 'custom' ? customRows : (lists[listKey] ?? []);
    final fieldsKey = listKey == 'custom' ? 'custom' : listKey;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'egx33', label: Text('EGX33')),
              ButtonSegment(value: 'all', label: Text('كل البورصة')),
            ],
            selected: {universe},
            onSelectionChanged: (s) {
              universe = s.first;
              _load();
            },
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              for (final k in ['intraday', 'swing', 'swing5', 'invest', 'consensus', 'excluded'])
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: ChoiceChip(
                    label: Text(listTitles[k]!),
                    selected: listKey == k,
                    onSelected: (_) => setState(() => listKey = k),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: ChoiceChip(
                  label: const Text('مدة مخصصة'),
                  selected: listKey == 'custom',
                  onSelected: (_) => setState(() => listKey = 'custom'),
                ),
              ),
            ],
          ),
        ),
        if (listKey == 'custom')
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('المدة (جلسات): '),
                DropdownButton<int>(
                  value: customH,
                  items: [for (final h in gridH) DropdownMenuItem(value: h, child: Text('$h'))],
                  onChanged: (v) {
                    if (v == null) return;
                    customH = v;
                    _loadCustom();
                  },
                ),
              ],
            ),
          ),
        Expanded(
          child: loading
              ? const Center(child: CircularProgressIndicator())
              : rows.isEmpty
                  ? const Center(child: Text('فاضية - جالسين بره السوق', style: TextStyle(fontSize: 16)))
                  : ListView.builder(
                      itemCount: rows.length,
                      itemBuilder: (_, i) => _card(rows[i], fieldsKey),
                    ),
        ),
      ],
    );
  }

  void _doSearch() {
    if (searchTicker.isEmpty || scores.isEmpty) return;
    Map<String, String>? row;
    for (final r in scores) {
      if (r['ticker'] == searchTicker) {
        row = r;
        break;
      }
    }
    if (row == null) return;
    final isIntra = searchH == 'انتراداي';
    final exp = isIntra ? (row['intra_exp'] ?? '') : (row['h${searchH}_exp'] ?? '');
    final prob = isIntra ? (row['intra_p'] ?? '') : (row['h${searchH}_p'] ?? '');
    final prec = isIntra ? (row['prec_intra'] ?? '') : (row['prec_${searchH}'] ?? '');
    final p = double.tryParse(prob) ?? 0;
    final conf = p >= 60 ? 'قوية' : (p >= 50 ? 'متوسطة' : 'ضعيفة');
    final close = double.tryParse(row['close'] ?? '') ?? 0;
    final target = close * (1 + (double.tryParse(exp) ?? 0) / 100);
    final sma20 = double.tryParse(row['sma20'] ?? '') ?? 0;
    final rsi = double.tryParse(row['rsi'] ?? '') ?? 0;
    final ext = (row['extended'] ?? '').toLowerCase() == 'true';
    String dec, entry, eentry;
    if (ext || rsi >= 70 || (sma20 > 0 && close > sma20 * 1.02)) {
      final tgt = sma20 > 0 ? (sma20 > close * 0.95 ? sma20 : close * 0.95) : close;
      if (tgt >= close) {
        dec = 'دخول حالا';
        entry = close.toStringAsFixed(2);
        eentry = exp;
      } else {
        dec = 'انتظار ${tgt.toStringAsFixed(2)}';
        entry = tgt.toStringAsFixed(2);
        eentry = (target - tgt) / tgt * 100;
        eentry = eentry.toStringAsFixed(2);
      }
    } else {
      dec = 'دخول حالا';
      entry = close.toStringAsFixed(2);
      eentry = exp;
    }
    setState(() {
      searchResult = {
        'ticker': searchTicker,
        'close': row['close'] ?? '',
        'rsi': rsi.toStringAsFixed(1),
        'rsi_range': row['rsi_range'] ?? '',
        'h': isIntra ? 'انتراداي (بيع آخر اليوم)' : '$searchH جلسات',
        'exp': exp,
        'target': target.toStringAsFixed(2),
        'dec': dec,
        'entry': entry,
        'eentry': eentry.toString(),
        'prob': prob,
        'conf': conf,
        'prec': prec,
        'state': ext ? 'ممتد - خطر مطاردة' : 'عادي',
        'reason': row['reason'] ?? '',
      };
    });
  }

  Widget _searchTab() {
    final tickers = scores.map((r) => r['ticker'] ?? '').where((t) => t.isNotEmpty).toList()..sort();
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'egx33', label: Text('EGX33')),
              ButtonSegment(value: 'all', label: Text('كل البورصة')),
            ],
            selected: {universe},
            onSelectionChanged: (s) {
              universe = s.first;
              searchResult = null;
              _load();
            },
          ),
        ),
        Autocomplete<String>(
          optionsBuilder: (v) => v.text.isEmpty
              ? const Iterable<String>.empty()
              : tickers.where((t) => t.contains(v.text.toUpperCase())),
          onSelected: (s) => searchTicker = s,
          fieldViewBuilder: (ctx, ctrl, focus, _) => TextField(
            controller: ctrl,
            focusNode: focus,
            decoration: const InputDecoration(labelText: 'السهم', border: OutlineInputBorder()),
            onChanged: (v) => searchTicker = v.toUpperCase(),
          ),
        ),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(
          value: searchH,
          decoration: const InputDecoration(labelText: 'المدة', border: OutlineInputBorder()),
          items: ['انتراداي', for (final h in gridH) '$h']
              .map((e) => DropdownMenuItem(value: e, child: Text(e == 'انتراداي' ? e : '$e جلسات')))
              .toList(),
          onChanged: (v) => setState(() => searchH = v ?? '5'),
        ),
        const SizedBox(height: 10),
        FilledButton(onPressed: _doSearch, child: const Text('بحث')),
        const SizedBox(height: 12),
        if (searchResult != null) _card(searchResult!, 'search'),
      ],
    );
  }

  Widget _recordTab() {
    final byList = <String, List<Map<String, String>>>{};
    for (final r in trades) {
      byList.putIfAbsent(r['list'] ?? '', () => []).add(r);
    }
    const order = ['انتراداي', 'مضاربة', 'مضاربة (5 أيام)', 'إجماع', 'استثمار'];
    final names = [for (final o in order) if (byList.containsKey(o)) o, for (final k in byList.keys) if (!order.contains(k)) k];
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'egx33', label: Text('EGX33')),
              ButtonSegment(value: 'all', label: Text('كل البورصة')),
            ],
            selected: {universe},
            onSelectionChanged: (s) {
              universe = s.first;
              _load();
            },
          ),
        ),
        if (asof.isNotEmpty)
          Text('الداتا بتاريخ: $asof', style: const TextStyle(fontWeight: FontWeight.bold)),
        Expanded(
          child: loading
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.all(10),
                  children: [
                    for (final n in names)
                      Builder(builder: (_) {
                        final done = byList[n]!.where((r) => r['result'] == 'كسبانة' || r['result'] == 'خسرانة').toList();
                        final w = done.where((r) => r['result'] == 'كسبانة').length;
                        final pend = byList[n]!.where((r) => r['result'] == 'معلقة').length;
                        final pct = done.isEmpty ? '-' : '${(w / done.length * 100).round()}%';
                        return Card(
                          child: ListTile(
                            title: Text(n, style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Text('كسبانة $w من ${done.length} ($pct)  •  معلقة: $pend'),
                            trailing: Icon(
                              Icons.circle,
                              color: done.isEmpty
                                  ? Colors.grey
                                  : (w / done.length >= 0.6 ? Colors.green : Colors.red),
                            ),
                          ),
                        );
                      }),
                  ],
                ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('قوايم الأسهم اليومية'),
        backgroundColor: navy,
        foregroundColor: Colors.white,
      ),
      body: tab == 0 ? _listsTab() : (tab == 1 ? _searchTab() : _recordTab()),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (i) => setState(() => tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.list), label: 'القوايم'),
          NavigationDestination(icon: Icon(Icons.search), label: 'بحث'),
          NavigationDestination(icon: Icon(Icons.history), label: 'السجل'),
        ],
      ),
    );
  }
}
