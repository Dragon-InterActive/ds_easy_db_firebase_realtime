import 'package:ds_easy_db/ds_easy_db.dart';
import 'package:ds_sync_contract/ds_sync_contract.dart';
import 'package:firebase_database/firebase_database.dart';

import 'realtime_sync_support.dart';

/// Makes the Firebase Realtime Database usable as the `remote` side of a sync
/// engine.
///
/// Purely additive: [FirebaseRealtimeDatabase] keeps working unchanged for
/// apps that only stream and never sync.
///
/// ```dart
/// engine.configure(
///   local: db.cache!,
///   remote: RealtimeSyncAdapter(),
///   config: const SyncConfig(collections: ['tasks']),
/// );
/// ```
///
/// ## What the backend has to provide
///
/// Delta pull orders children by [updatedAtField], which needs an index in the
/// security rules:
///
/// ```json
/// { "rules": { "tasks": { ".indexOn": "updatedAt" } } }
/// ```
///
/// The field must be written with [DatabaseRepository.serverTS], so the
/// backend assigns the value.
///
/// A removed child cannot appear in any query, so
/// [SyncCapabilities.supportsDeltaDeletes] is only true when [deletedField] is
/// configured — that is, when the tree marks deletions with a flag instead of
/// removing the node. Otherwise the engine degrades to full pulls.
class RealtimeSyncAdapter implements SyncRemoteAdapter {
  /// Creates an adapter over [database] (defaults to the default instance).
  RealtimeSyncAdapter({
    FirebaseDatabase? database,
    this.updatedAtField = 'updatedAt',
    this.deletedField,
    this.pageSize = 200,
    this.fetchAnchorsAfterPush = true,
  })  : _database = database,
        assert(pageSize > 0, 'pageSize must be positive');

  final FirebaseDatabase? _database;

  /// The child field holding the server timestamp deltas are ordered by.
  ///
  /// Must be listed under `.indexOn` in the security rules, or the backend
  /// sorts client-side and the delta query loses its point.
  final String updatedAtField;

  /// Optional boolean field marking a child as remotely deleted.
  ///
  /// Set this only if the tree uses remote soft-deletes; it is what makes
  /// delta deletes possible at all.
  final String? deletedField;

  /// How many children one pull page fetches.
  final int pageSize;

  /// Whether to read the server-assigned timestamps back after a push.
  ///
  /// Defaults to true. `ServerValue.timestamp` is resolved on the backend, so
  /// without this read the pushed records carry no conflict anchor until the
  /// next pull.
  final bool fetchAnchorsAfterPush;

  FirebaseDatabase get _db => _database ?? FirebaseDatabase.instance;

  @override
  SyncCapabilities get capabilities => SyncCapabilities(
        supportsTimestamps: true,
        supportsVersioning: false,
        supportsContentHash: false,
        supportsDeltaPull: true,
        supportsDeltaDeletes: deletedField != null,
        // A multi-path update is applied atomically by the backend.
        supportsBatchWrite: true,
      );

  @override
  SyncError mapError(Object error, StackTrace stackTrace) =>
      mapRealtimeError(error, stackTrace);

  @override
  Future<DeltaResult> pullSince(String collection, Object? cursor) async {
    try {
      final position = RealtimeCursor.decode(cursor);

      Query query = _db.ref(collection).orderByChild(updatedAtField);
      if (position != null) {
        query = query.startAfter(position.updatedAtMillis, key: position.key);
      } else {
        // `orderByChild` sorts children *without* the field (and boolean
        // values) first. They can never advance the cursor, so a first page
        // made only of them would be re-read forever and block every newer
        // child. Starting after `true` skips null and boolean values; like
        // Firestore, children without a timestamp are simply not synced.
        query = query.startAfter(true);
      }

      final snapshot = await query.limitToFirst(pageSize).get();
      if (!snapshot.exists) {
        return DeltaResult(nextCursor: cursor);
      }

      final changed = <RemoteRecord>[];
      final deleted = <String>[];
      final flagField = deletedField;

      String? lastKey;
      int? lastMillis;
      var count = 0;

      // `snapshot.children` preserves the query order, unlike the raw value
      // map — reading the map would lose the ordering the cursor depends on.
      for (final child in snapshot.children) {
        final key = child.key;
        final data = asDocument(child.value);
        if (key == null || data == null) continue;

        count++;
        final rawUpdatedAt = data[updatedAtField];
        if (rawUpdatedAt is int) {
          lastMillis = rawUpdatedAt;
          lastKey = key;
        }

        if (flagField != null && data[flagField] == true) {
          deleted.add(key);
          continue;
        }
        changed.add(RemoteRecord(
          id: key,
          data: data,
          anchor: realtimeAnchorFrom(data, updatedAtField),
        ));
      }

      final advanced = lastMillis != null && lastKey != null;
      return DeltaResult(
        changed: changed,
        deleted: deleted,
        // Without a usable timestamp on the last child the cursor cannot move;
        // re-reading that page is better than skipping past it.
        nextCursor: advanced
            ? RealtimeCursor(updatedAtMillis: lastMillis, key: lastKey).encode()
            : cursor,
        hasMore: count == pageSize && advanced,
      );
    } catch (error, stackTrace) {
      throw mapRealtimeError(error, stackTrace);
    }
  }

  @override
  Future<List<PushResult>> pushBatch(List<PushItem> items) async {
    if (items.isEmpty) return const <PushResult>[];

    try {
      final updates = <String, Object?>{};
      for (final item in items) {
        final path = '${item.collection}/${item.id}';
        if (item.isDelete) {
          final flagField = deletedField;
          if (flagField == null) {
            updates[path] = null; // null removes the node.
          } else {
            updates['$path/$flagField'] = true;
            updates['$path/$updatedAtField'] = ServerValue.timestamp;
          }
          continue;
        }
        updates[path] = _resolveServerTimestamps(item.data!);
      }

      await _db.ref().update(updates);
    } catch (error, stackTrace) {
      // A multi-path update is atomic: on failure nothing landed, and the
      // uniform status tells the engine to keep every record dirty.
      final syncError = mapRealtimeError(error, stackTrace);
      return <PushResult>[
        for (final item in items)
          PushResult(
            id: item.id,
            status: syncError.kind == SyncErrorKind.conflict
                ? PushStatus.conflict
                : PushStatus.failed,
            error: syncError,
          ),
      ];
    }

    // The update landed. Reading the anchors back is optional: if it fails,
    // the writes are still successful — they just carry no conflict anchor
    // until the next pull refreshes it.
    Map<String, RemoteAnchor> anchors;
    try {
      anchors = await _readBackAnchors(items);
    } catch (_) {
      anchors = const <String, RemoteAnchor>{};
    }

    return <PushResult>[
      for (final item in items)
        PushResult(
          id: item.id,
          status: PushStatus.success,
          newAnchor: anchors['${item.collection}/${item.id}'],
        ),
    ];
  }

  Future<Map<String, RemoteAnchor>> _readBackAnchors(
    List<PushItem> items,
  ) async {
    if (!fetchAnchorsAfterPush) return const <String, RemoteAnchor>{};

    final anchors = <String, RemoteAnchor>{};
    for (final item in items) {
      if (item.isDelete && deletedField == null) continue;
      final snapshot = await _db.ref('${item.collection}/${item.id}').get();
      final data = asDocument(snapshot.value);
      if (data == null) continue;
      // Keyed by path: one batch may contain the same id in two collections.
      anchors['${item.collection}/${item.id}'] =
          realtimeAnchorFrom(data, updatedAtField);
    }
    return anchors;
  }

  Map<String, Object?> _resolveServerTimestamps(Map<String, dynamic> data) {
    return <String, Object?>{
      for (final entry in data.entries)
        entry.key: entry.value == DatabaseRepository.serverTS
            ? ServerValue.timestamp
            : entry.value,
    };
  }
}
