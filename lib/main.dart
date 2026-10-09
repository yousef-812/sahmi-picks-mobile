import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:csv/csv.dart';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'ml/bg_task.dart';
import 'ml/inference.dart';
import 'ml/refresh.dart'
    show dataDir, refreshUniverse, writeCmd, listPartials;

final bgProgress = ValueNotifier<Map<String, dynamic>>({});
final bgEvent = ValueNotifier<Map<String, dynamic>?>(null);

void _bgRouter(Object data) {
  if (data is Map) {
    final m = Map<String, dynamic>.from(data);
    if (m['type'] == 'progress') {
      bgProgress.value = m;
    } else {
      bgEvent.value = m;
    }
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'picks_refresh',
        channelName: 'تحديث البيانات',
        channelDescription: 'تحديث بيانات الأسهم في الخلفية مع إشعار تقدم',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions:
          const IOSNotificationOptions(showNotification: true, playSound: false),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        autoRunOnBoot: false,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
    FlutterForegroundTask.initCommunicationPort();
    FlutterForegroundTask.addTaskDataCallback(_bgRouter);
  } catch (_) {}
  runApp(const PicksApp());
}

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

List<Map<String, String>> parseCsv(String raw) {
  final clean = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  final rows = const CsvToListConverter(eol: '\n').convert(clean);
  if (rows.isEmpty) return [];
  final head = rows.first.map((e) => e.toString()).toList();
  return rows.skip(1).where((r) => r.isNotEmpty).map((r) {
    final m = <String, String>{};
    for (var i = 0; i < head.length && i < r.length; i++) {
      m[head[i]] = r[i].toString();
    }
    return m;
  }).toList();
}

Future<List<Map<String, String>>> loadCsv(String path) async {
  try {
    return parseCsv(await rootBundle.loadString(path));
  } catch (_) {
    return [];
  }
}

/// On-device refresh output overrides bundled assets when present.
Future<String?> docsText(String name) async {
  try {
    final dir = await dataDir();
    final f = File('${dir.path}/$name');
    if (await f.exists()) return await f.readAsString();
  } catch (_) {}
  return null;
}

Future<List<Map<String, String>>> loadTable(String universe, String name) async {
  final file = '${universe}_$name.csv';
  final t = await docsText(file);
  if (t != null) {
    try {
      return parseCsv(t);
    } catch (_) {}
  }
  return loadCsv('assets/data/$file');
}

Future<String> loadAsof(String universe) async {
  try {
    final t = await docsText('meta.json');
    if (t != null) {
      final m = jsonDecode(t) as Map<String, dynamic>;
      final u = m[universe] as Map<String, dynamic>?;
      if (u != null && u['asof'] != null) return u['asof'].toString();
    }
  } catch (_) {}
  try {
    final t = await rootBundle.loadString('assets/data/meta.json');
    final m = jsonDecode(t) as Map<String, dynamic>;
    final u = m[universe] as Map<String, dynamic>?;
    if (u != null && u['asof'] != null) return u['asof'].toString();
  } catch (_) {}
  return '';
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
  String asofSrc = '';
  Map<String, String> diag = {};
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
    bgEvent.addListener(_onBgEvent);
    _load();
    try {
      FlutterForegroundTask.isRunningService.then((r) {
        if (r && mounted) _showBgProgress();
      }).catchError((_) {});
    } catch (_) {}
  }

  @override
  void dispose() {
    bgEvent.removeListener(_onBgEvent);
    try {
      FlutterForegroundTask.removeTaskDataCallback(_bgRouter);
    } catch (_) {}
    super.dispose();
  }

  bool _bgDlgOpen = false;
  final List<String> _bgSummaries = [];

  void _onBgEvent() {
    final e = bgEvent.value;
    if (e == null || !mounted) return;
    bgEvent.value = null;
    if (e['type'] == 'universe_done') {
      var s = '${e['u']}: ${e['ok']} ناجح / ${e['fail']} فاشل';
      if (e['resumed'] == true) s += ' (استكمال)';
      if (e['restartedFresh'] == true) s += ' (جلسة جديدة - بدأ من جديد)';
      _bgSummaries.add(s);
      return;
    }
    if (e['type'] == 'done') {
      if (_bgDlgOpen && mounted) {
        Navigator.of(context).pop();
        _bgDlgOpen = false;
      }
      if (e['ok'] == true) {
        _load();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('تم التحديث: ${_bgSummaries.join(' • ')}')));
        }
      } else {
        if (mounted) {
          showDialog(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text('فشل التحديث'),
              content: Text('${e['error'] ?? 'خطأ غير معروف'}\nالتقدم محفوظ ويمكن الاستكمال لاحقاً.'),
              actions: [
                TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('حسناً'))
              ],
            ),
          );
        }
      }
    }
  }

  void _showBgProgress() {
    if (_bgDlgOpen) return;
    _bgDlgOpen = true;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('تحديث البيانات (خلفية)'),
        content: ValueListenableBuilder<Map<String, dynamic>>(
          valueListenable: bgProgress,
          builder: (_, v, __) {
            final d = v['done'], t = v['total'];
            final txt = (d == null || t == null) ? 'بدء...' : '${v['u']}: ${v['ticker']} ($d/$t)';
            final frac = (d is num && t is num && t > 0) ? (d / t).clamp(0.0, 1.0) : null;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                LinearProgressIndicator(value: frac),
                const SizedBox(height: 12),
                Text(txt, style: const TextStyle(fontSize: 13)),
                const SizedBox(height: 6),
                const Text('يمكنك استخدام الموبايل عادي - تابع من الإشعارات',
                    style: TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () async {
              try {
                await FlutterForegroundTask.stopService();
              } catch (_) {}
              if (mounted) {
                Navigator.of(context).pop();
                _bgDlgOpen = false;
              }
            },
            child: const Text('إيقاف مؤقت (يُحفظ التقدم)'),
          ),
        ],
      ),
    ).then((_) => _bgDlgOpen = false);
  }

  Future<void> _refreshForeground(String mode) async {
    final prog = ValueNotifier('بدء التحديث...');
    if (!mounted) return;
    _bgDlgOpen = true;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('تحديث البيانات'),
        content: ValueListenableBuilder<String>(
          valueListenable: prog,
          builder: (_, v, __) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const LinearProgressIndicator(),
              const SizedBox(height: 12),
              Text(v, style: const TextStyle(fontSize: 13)),
            ],
          ),
        ),
      ),
    ).then((_) => _bgDlgOpen = false);
    try {
      final parts = <String>[];
      for (final u in ['egx33', 'all']) {
        final rep = await refreshUniverse(u, fresh: mode == 'fresh',
            onProgress: (d, t, tk) async {
          prog.value = '$u: $tk ($d/$t)';
        });
        parts.add('$u: ${rep.ok} ناجح / ${rep.fail} فاشل');
      }
      if (!mounted) return;
      Navigator.of(context).pop();
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تم التحديث: ${parts.join(' • ')}')));
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('فشل التحديث'),
          content: Text('$e'),
          actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('حسناً'))],
        ),
      );
    } finally {
      prog.dispose();
    }
  }

  Future<void> _load() async {
    setState(() => loading = true);
    final u = universe;
    final l = <String, List<Map<String, String>>>{};
    final dg = <String, String>{};
    for (final k in ['intraday', 'swing', 'swing5', 'invest', 'consensus', 'excluded']) {
      try {
        l[k] = await loadTable(u, k);
        dg[k] = '${l[k]!.length} صف';
      } catch (e) {
        l[k] = [];
        dg[k] = 'خطأ: $e';
      }
    }
    List<Map<String, String>> sc = [];
    try {
      sc = await loadTable(u, 'scores');
      dg['scores'] = '${sc.length} سهم';
    } catch (e) {
      dg['scores'] = 'خطأ: $e';
    }
    List<Map<String, String>> tr = [];
    try {
      tr = await loadTable(u, 'trades');
      dg['trades'] = '${tr.length} صفقة';
    } catch (e) {
      dg['trades'] = 'خطأ: $e';
    }
    final asofV = await loadAsof(u);
    String src = '';
    try {
      final t = await docsText('meta.json');
      src = t != null ? 'محدّثة من الجهاز' : 'مدمجة مع التطبيق';
    } catch (_) {
      src = 'مدمجة مع التطبيق';
    }
    final cu = await loadTable(u, 'custom_$customH');
    if (!mounted) return;
    setState(() {
      lists = l;
      scores = sc;
      trades = tr;
      asof = asofV;
      asofSrc = src;
      customRows = cu;
      searchResult = null;
      loading = false;
      diag = dg;
    });
  }

  Future<void> _loadCustom() async {
    final cu = await loadTable(universe, 'custom_$customH');
    if (!mounted) return;
    setState(() => customRows = cu);
  }

  Future<void> _refreshAll() async {
    final partials = await listPartials();
    var mode = 'fresh';
    if (partials.isNotEmpty && mounted) {
      final desc = partials
          .map((p) =>
              '${p['tag'] == 'egx33' ? 'EGX33' : 'كل البورصة'}: ${p['count']} سهم محفوظ بتاريخ ${p['maxDate']}')
          .join('\n');
      mode = await showDialog<String>(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text('يوجد تحديث ناقص'),
              content: Text('$desc\n\nلو نزلت جلسة جديدة سيرفض الاستكمال ويبدأ من جديد تلقائياً.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.of(context).pop('resume'),
                    child: const Text('استكمال')),
                TextButton(
                    onPressed: () => Navigator.of(context).pop('fresh'),
                    child: const Text('بدء من جديد')),
                TextButton(
                    onPressed: () => Navigator.of(context).pop('cancel'),
                    child: const Text('إلغاء')),
              ],
            ),
          ) ??
          'cancel';
      if (mode == 'cancel') return;
    }
    await writeCmd(mode);
    var useBg = false;
    try {
      var perm = await FlutterForegroundTask.checkNotificationPermission();
      if (perm != NotificationPermission.granted) {
        perm = await FlutterForegroundTask.requestNotificationPermission();
      }
      if (perm == NotificationPermission.granted) {
        await FlutterForegroundTask.startService(
          serviceTypes: [ForegroundServiceTypes.dataSync],
          notificationTitle: 'تحديث القوايم',
          notificationText: 'بدء التحديث...',
          callback: startCallback,
        );
        useBg = true;
      }
    } catch (_) {
      useBg = false;
    }
    if (!useBg) {
      await _refreshForeground(mode);
      return;
    }
    _bgSummaries.clear();
    if (mounted) _showBgProgress();
  }

  Future<void> _selfTest() async {
    String msg;
    try {
      final raw = await rootBundle.loadString('assets/parity_test.json');
      final t = jsonDecode(raw) as Map<String, dynamic>;
      final rows = (t['rows'] as List)
          .map((r) => (r as List).map((v) => v == null ? double.nan : (v as num).toDouble()).toList())
          .toList();
      var worst = 0.0;
      for (final key in ['h5', 'intra']) {
        final reg = HgbModel.fromJson(
            await rootBundle.loadString('assets/models/egx33_${key}_reg.json'), false);
        final clf = HgbModel.fromJson(
            await rootBundle.loadString('assets/models/egx33_${key}_clf.json'), true);
        final er = (t['expect'][key]['reg'] as List).map((v) => (v as num).toDouble()).toList();
        final ec = (t['expect'][key]['clf'] as List).map((v) => (v as num).toDouble()).toList();
        for (var i = 0; i < rows.length; i++) {
          final d1 = (reg.predictReg(rows[i]) - er[i]).abs();
          final d2 = (clf.predictProba(rows[i]) - ec[i]).abs();
          if (d1 > worst) worst = d1;
          if (d2 > worst) worst = d2;
        }
      }
      msg = worst < 1e-3
          ? 'النماذج سليمة ✓ (أكبر فرق $worst على ${rows.length} صف)'
          : 'تحذير: فرق كبير $worst — راجع ملفات النماذج';
    } catch (e) {
      msg = 'تعذر الفحص: $e';
    }
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('فحص سلامة النماذج'),
        content: Text(msg),
        actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('حسناً'))],
      ),
    );
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
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Text(
                          listKey == 'consensus'
                              ? 'فاضية - جالسين بره السوق'
                              : 'لا توجد بيانات\n${diag.entries.map((e) => '${e.key}: ${e.value}').join('\n')}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 14),
                        ),
                      ),
                    )
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
    final fr = row;
    final isIntra = searchH == 'انتراداي';
    final exp = isIntra ? (fr['intra_exp'] ?? '') : (fr['h' + searchH + '_exp'] ?? '');
    final prob = isIntra ? (fr['intra_p'] ?? '') : (fr['h' + searchH + '_p'] ?? '');
    final prec = isIntra ? (fr['prec_intra'] ?? '') : (fr['prec_' + searchH] ?? '');
    final p = double.tryParse(prob) ?? 0;
    final conf = p >= 60 ? 'قوية' : (p >= 50 ? 'متوسطة' : 'ضعيفة');
    final close = double.tryParse(fr['close'] ?? '') ?? 0;
    final target = close * (1 + (double.tryParse(exp) ?? 0) / 100);
    final sma20 = double.tryParse(fr['sma20'] ?? '') ?? 0;
    final rsi = double.tryParse(fr['rsi'] ?? '') ?? 0;
    final ext = (fr['extended'] ?? '').toLowerCase() == 'true';
    String dec, entry;
    String eentry;
    if (ext || rsi >= 70 || (sma20 > 0 && close > sma20 * 1.02)) {
      final tgt = sma20 > 0 ? (sma20 > close * 0.95 ? sma20 : close * 0.95) : close;
      if (tgt >= close) {
        dec = 'دخول حالا';
        entry = close.toStringAsFixed(2);
        eentry = exp;
      } else {
        dec = 'انتظار ${tgt.toStringAsFixed(2)}';
        entry = tgt.toStringAsFixed(2);
        eentry = (((target - tgt) / tgt * 100)).toStringAsFixed(2);
      }
    } else {
      dec = 'دخول حالا';
      entry = close.toStringAsFixed(2);
      eentry = exp;
    }
    setState(() {
      searchResult = {
        'ticker': searchTicker,
        'close': fr['close'] ?? '',
        'rsi': rsi.toStringAsFixed(1),
        'rsi_range': fr['rsi_range'] ?? '',
        'h': isIntra ? 'انتراداي (بيع آخر اليوم)' : '$searchH جلسات',
        'exp': exp,
        'target': target.toStringAsFixed(2),
        'dec': dec,
        'entry': entry,
        'eentry': eentry,
        'prob': prob,
        'conf': conf,
        'prec': prec,
        'state': ext ? 'ممتد - خطر مطاردة' : 'عادي',
        'reason': fr['reason'] ?? '',
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
          Text('الداتا بتاريخ: $asof ($asofSrc)', style: const TextStyle(fontWeight: FontWeight.bold)),
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
        actions: [
          IconButton(
            icon: const Icon(Icons.verified),
            tooltip: 'فحص النماذج',
            onPressed: _selfTest,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'تحديث البيانات من البورصة',
            onPressed: _refreshAll,
          ),
        ],
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
