import 'package:comicollect/app_controller.dart';
import 'package:comicollect/models/catalog_issue.dart';
import 'package:comicollect/models/comic.dart';

class RecordingController extends AppController {
  RecordingController({List<Comic> comics = const []}) {
    this.comics = List.of(comics);
    loading = false;
    autoSync = false;
  }

  final List<Comic> saved = [];
  final List<List<Comic>> savedBatches = [];
  final List<Map<CatalogIssue, bool>> scanBatches = [];
  final List<Comic> removed = [];
  final List<AddCall> additions = [];
  int syncCalls = 0;
  int syncResetCalls = 0;
  int initCalls = 0;
  bool? lastSyncForced;

  void replaceComics(List<Comic> value) {
    comics = List.of(value);
    notifyListeners();
  }

  @override
  Future<void> init() async {
    initCalls++;
    loading = false;
    startupError = null;
    notifyListeners();
  }

  @override
  Future<void> save(Comic comic) async {
    saved.add(comic);
    final byId = {for (final item in comics) item.id: item};
    if (comic.deleted) {
      byId.remove(comic.id);
    } else {
      byId[comic.id] = comic;
    }
    comics = byId.values.toList(growable: false);
    notifyListeners();
  }

  @override
  Future<void> saveAll(Iterable<Comic> changes) async {
    final batch = changes.toList(growable: false);
    savedBatches.add(batch);
    final byId = {for (final item in comics) item.id: item};
    for (final comic in batch) {
      if (comic.deleted) {
        byId.remove(comic.id);
      } else {
        byId[comic.id] = comic;
      }
    }
    comics = byId.values.toList(growable: false);
    notifyListeners();
  }

  @override
  Future<void> saveScanResults(Map<CatalogIssue, bool> results) async {
    scanBatches.add(Map.of(results));
  }

  @override
  Future<void> remove(Comic comic) async {
    removed.add(comic);
    await save(comic.copyWith(deleted: true));
  }

  @override
  Future<void> sync({bool force = false}) async {
    syncCalls++;
    lastSyncForced = force;
  }

  @override
  Future<void> resetSyncServerBinding() async {
    syncResetCalls++;
    online = false;
    lastSyncAt = null;
    syncMessage = 'Spremno za povezivanje s novim serverom';
    notifyListeners();
  }

  @override
  Future<void> updatePreferences({
    bool? darkMode,
    String? accent,
    bool? comicTitles,
    bool? showStatistics,
    bool? autoSync,
    bool? newIssueNotifications,
  }) async {
    if (darkMode != null) this.darkMode = darkMode;
    if (accent != null) this.accent = accent;
    if (comicTitles != null) this.comicTitles = comicTitles;
    if (showStatistics != null) this.showStatistics = showStatistics;
    if (autoSync != null) this.autoSync = autoSync;
    if (newIssueNotifications != null) {
      this.newIssueNotifications = newIssueNotifications;
    }
    notifyListeners();
  }

  @override
  Future<void> add({
    required String series,
    required String edition,
    required int number,
    required String title,
    String publisher = '',
    int? year,
    bool owned = true,
    bool read = false,
    String condition = 'F',
    double? purchasePrice,
    double? estimatedValue,
    bool duplicate = false,
    String loanedTo = '',
    String notes = '',
    int rating = 0,
    int? pageCount,
    String writer = '',
    String artist = '',
  }) async {
    additions.add(
      AddCall(
        series: series,
        edition: edition,
        number: number,
        title: title,
        publisher: publisher,
        year: year,
        owned: owned,
        read: read,
        condition: condition,
        purchasePrice: purchasePrice,
        estimatedValue: estimatedValue,
        duplicate: duplicate,
        loanedTo: loanedTo,
        notes: notes,
        rating: rating,
        pageCount: pageCount,
        writer: writer,
        artist: artist,
      ),
    );
  }
}

class AddCall {
  const AddCall({
    required this.series,
    required this.edition,
    required this.number,
    required this.title,
    required this.publisher,
    required this.year,
    required this.owned,
    required this.read,
    required this.condition,
    required this.purchasePrice,
    required this.estimatedValue,
    required this.duplicate,
    required this.loanedTo,
    required this.notes,
    required this.rating,
    required this.pageCount,
    required this.writer,
    required this.artist,
  });

  final String series;
  final String edition;
  final int number;
  final String title;
  final String publisher;
  final int? year;
  final bool owned;
  final bool read;
  final String condition;
  final double? purchasePrice;
  final double? estimatedValue;
  final bool duplicate;
  final String loanedTo;
  final String notes;
  final int rating;
  final int? pageCount;
  final String writer;
  final String artist;
}

Comic testComic(
  int number, {
  String? id,
  String series = 'Dylan Dog',
  String edition = 'Regularna (L)',
  String? title,
  String publisher = 'Ludens',
  int? year = 2002,
  bool owned = true,
  bool read = false,
  String condition = 'F',
  double? purchasePrice,
  double? estimatedValue,
  bool duplicate = false,
  String loanedTo = '',
  String notes = '',
  String coverAsset = '',
  int rating = 0,
  int? pageCount,
  String writer = '',
  String artist = '',
  bool deleted = false,
}) => Comic(
  id: id ?? 'test-$series-$edition-$number',
  series: series,
  edition: edition,
  number: number,
  title: title ?? 'Test $number',
  publisher: publisher,
  year: year,
  owned: owned,
  read: read,
  condition: condition,
  purchasePrice: purchasePrice,
  estimatedValue: estimatedValue,
  duplicate: duplicate,
  loanedTo: loanedTo,
  notes: notes,
  coverAsset: coverAsset,
  rating: rating,
  pageCount: pageCount,
  writer: writer,
  artist: artist,
  deleted: deleted,
  updatedAt: number,
);

CatalogIssue testIssue(
  int number, {
  String? id,
  String sourceEdition = 'DDLU',
  String edition = 'Regularna (L)',
  String? title,
  String? coverAsset,
}) => CatalogIssue(
  id: id ?? 'catalog-$sourceEdition-$number',
  sourceEdition: sourceEdition,
  series: 'Dylan Dog',
  edition: edition,
  number: number,
  title: title ?? 'Test $number',
  publisher: 'Ludens',
  coverAsset: coverAsset,
);
