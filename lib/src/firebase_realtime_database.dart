import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:ds_easy_db/ds_easy_db.dart';

class FirebaseRealtimeDatabase implements DatabaseStreamRepository {
  final FirebaseOptions? options;
  FirebaseDatabase? _database;

  FirebaseRealtimeDatabase({this.options});

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

      final data = event.snapshot.value;
      if (data is Map) {
        return Map<String, dynamic>.from(data);
      }
      return null;
    });
  }

  @override
  Stream<Map<String, dynamic>?> watchAll(String collection) {
    return database.ref(collection).onValue.map((event) {
      if (!event.snapshot.exists) return null;

      final data = event.snapshot.value;
      if (data is Map) {
        return Map<String, dynamic>.from(data);
      }
      return null;
    });
  }

  @override
  Stream<List<Map<String, dynamic>>> watchQuery(
    String collection, {
    Map<String, dynamic> where = const {},
  }) {
    return database.ref(collection).onValue.map((event) {
      if (!event.snapshot.exists) return <Map<String, dynamic>>[];

      final data = event.snapshot.value;
      if (data is! Map) return <Map<String, dynamic>>[];

      final items = <Map<String, dynamic>>[];

      data.forEach((key, value) {
        if (value is Map) {
          final item = Map<String, dynamic>.from(value);
          item['id'] = key;

          // Filtern
          if (where.isEmpty) {
            items.add(item);
          } else {
            bool matches = true;
            for (var entry in where.entries) {
              if (item[entry.key] != entry.value) {
                matches = false;
                break;
              }
            }
            if (matches) items.add(item);
          }
        }
      });
      return items;
    });
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
