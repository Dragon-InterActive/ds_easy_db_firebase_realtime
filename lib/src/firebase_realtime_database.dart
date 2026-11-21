import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:ds_easy_db/ds_easy_db.dart';

/// Firebase Realtime Database implementation of [DatabaseStreamRepository].
///
/// Provides real-time data synchronization with streaming support. Optimized
/// for low-latency updates and live data across connected clients.
///
/// Features:
/// - Real-time data synchronization
/// - Low latency updates
/// - Offline support with automatic sync
/// - Reactive streams for live data
/// - Cross-platform support
///
/// Firebase initialization:
/// ```dart
/// db.configure(
///   stream: FirebaseRealtimeDatabase(
///     options: DefaultFirebaseOptions.currentPlatform,
///   ),
///   // ...
/// );
/// ```
class FirebaseRealtimeDatabase implements DatabaseStreamRepository {
  /// Optional Firebase configuration options.
  ///
  /// If provided, Firebase will be automatically initialized in [init].
  /// If null, Firebase must be initialized manually before using this database.
  final FirebaseOptions? options;

  FirebaseDatabase? _database;

  /// Creates a new Firebase Realtime Database instance.
  ///
  /// [options] Optional Firebase configuration. If provided, Firebase will be
  /// initialized automatically. Otherwise, ensure Firebase is initialized manually.
  FirebaseRealtimeDatabase({this.options});

  /// Returns the Firebase Database instance.
  FirebaseDatabase get database {
    _database ??= FirebaseDatabase.instance;
    return _database!;
  }

  @override
  Future<void> init() async {
    if (Firebase.apps.isEmpty) {
      if (options == null) {
        throw Exception(
          'Firebase has not been initialized. Please provide FirebaseOptions '
          'in the FirebaseRealtimeDatabase constructor or initialize Firebase manually.',
        );
      }
      await Firebase.initializeApp(options: options);
    }
    _database = FirebaseDatabase.instance;
  }

  @override
  Stream<Map<String, dynamic>?> watch(String collection, String id) {
    return database.ref(collection).child(id).onValue.map((event) {
      if (!event.snapshot.exists) return null;
      return _asDocument(event.snapshot.value);
    });
  }

  @override
  Stream<Map<String, dynamic>?> watchAll(String collection) {
    return database.ref(collection).onValue.map((event) {
      if (!event.snapshot.exists) return null;
      final children = _children(event.snapshot.value);
      return children.isEmpty ? null : children;
    });
  }

  /// Watches the documents matching [where], each with its key under `id`.
  ///
  /// A document that carries its own `id` field keeps it.
  @override
  Stream<List<Map<String, dynamic>>> watchQuery(
    String collection, {
    Map<String, dynamic> where = const {},
  }) {
    return database.ref(collection).onValue.map((event) {
      if (!event.snapshot.exists) return <Map<String, dynamic>>[];

      final items = <Map<String, dynamic>>[];
      for (final entry in _children(event.snapshot.value).entries) {
        final document = entry.value;
        if (document is! Map<String, dynamic>) continue;
        if (!_matches(document, where)) continue;
        items.add(<String, dynamic>{'id': entry.key, ...document});
      }
      return items;
    });
  }

  bool _matches(Map<String, dynamic> document, Map<String, dynamic> where) {
    for (final entry in where.entries) {
      if (document[entry.key] != entry.value) return false;
    }
    return true;
  }

  /// The children of a collection node, keyed by their key.
  ///
  /// The Realtime Database turns a node whose keys are all small integers
  /// (`"0"`, `"1"`, ...) into a `List` — with `null` holes for missing keys —
  /// instead of a `Map`. Both shapes are accepted here.
  static Map<String, dynamic> _children(Object? value) {
    if (value is Map) {
      return <String, dynamic>{
        for (final entry in value.entries)
          if (entry.value != null)
            entry.key.toString(): _normalize(entry.value),
      };
    }
    if (value is List) {
      return <String, dynamic>{
        for (var i = 0; i < value.length; i++)
          if (value[i] != null) '$i': _normalize(value[i]),
      };
    }
    return <String, dynamic>{};
  }

  static Map<String, dynamic>? _asDocument(Object? value) {
    if (value is Map) return _normalize(value) as Map<String, dynamic>;
    // An integer-keyed document arrives as a List; keep it addressable.
    if (value is List) return _children(value);
    return null;
  }

  /// Converts the `Map<Object?, Object?>` values the SDK returns — nested ones
  /// included — into `Map<String, dynamic>`.
  static Object? _normalize(Object? value) {
    if (value is Map) {
      return <String, dynamic>{
        for (final entry in value.entries)
          entry.key.toString(): _normalize(entry.value),
      };
    }
    if (value is List) return value.map(_normalize).toList();
    return value;
  }

  @override
  Future<void> set(
    String collection,
    String id,
    Map<String, dynamic> data,
  ) async {
    final processedData = data.map((key, value) {
      if (value == DatabaseRepository.serverTS) {
        return MapEntry(key, ServerValue.timestamp);
      }
      return MapEntry(key, value);
    });

    await database.ref(collection).child(id).set(processedData);
  }

  @override
  Future<void> update(
    String collection,
    String id,
    Map<String, dynamic> data,
  ) async {
    final processedData = data.map((key, value) {
      if (value == DatabaseRepository.serverTS) {
        return MapEntry(key, ServerValue.timestamp);
      }
      return MapEntry(key, value);
    });

    await database.ref(collection).child(id).update(processedData);
  }

  @override
  Future<void> delete(String collection, String id) async {
    await database.ref(collection).child(id).remove();
  }
}
