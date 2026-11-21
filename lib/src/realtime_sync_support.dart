import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:ds_sync_contract/ds_sync_contract.dart';

/// A delta cursor for the Realtime Database, paired with the last key.
///
/// `ServerValue.timestamp` resolves to epoch milliseconds, and several
/// children can share one value. Pairing it with the last key lets the next
/// page start with `startAfter(value, key: key)`, so a group of children with
/// the same timestamp is neither cut in half nor fetched forever.
///
/// Serialises to a `String`, which the sync metadata store can persist on both
/// Hive and SQLite.
class RealtimeCursor {
  /// Creates a keyset cursor.
  const RealtimeCursor({required this.updatedAtMillis, required this.key});

  /// The `updatedAt` value of the last child of the previous page.
  final int updatedAtMillis;

  /// That child's key — the tie-breaker within one timestamp.
  final String key;

  /// Separator between the parts. A Realtime Database key cannot contain it.
  static const String separator = '/';

  /// The cursor as a `DateTime`, for anchors and reporting.
  DateTime get updatedAt =>
      DateTime.fromMillisecondsSinceEpoch(updatedAtMillis, isUtc: true);

  /// Encodes the cursor as `<unixMillis>/<key>`.
  String encode() => '$updatedAtMillis$separator$key';

  /// Decodes a cursor produced by [encode].
  ///
  /// Returns `null` for anything unparseable, which restarts the pull from the
  /// beginning — expensive, never wrong.
  static RealtimeCursor? decode(Object? raw) {
    if (raw is RealtimeCursor) return raw;
    if (raw is! String) return null;

    final split = raw.indexOf(separator);
    if (split <= 0 || split == raw.length - 1) return null;

    final millis = int.tryParse(raw.substring(0, split));
    if (millis == null) return null;

    return RealtimeCursor(
      updatedAtMillis: millis,
      key: raw.substring(split + 1),
    );
  }

  @override
  String toString() => 'RealtimeCursor(${encode()})';
}

/// Translates Realtime Database failures into the engine's vocabulary.
///
/// As with every adapter, this doubles as the connectivity check: an
/// unreachable backend has to surface as [SyncErrorKind.transient].
SyncError mapRealtimeError(Object error, StackTrace stackTrace) {
  if (error is SyncError) return error;

  if (error is FirebaseException) {
    return SyncError(
      _kindForCode(error.code),
      message: '[${error.code}] ${error.message ?? ''}'.trim(),
      cause: error,
      stackTrace: stackTrace,
    );
  }

  if (error is SocketException || error is HttpException) {
    return SyncError(
      SyncErrorKind.transient,
      message: 'The backend could not be reached.',
      cause: error,
      stackTrace: stackTrace,
    );
  }

  return SyncError(
    SyncErrorKind.transient,
    message: 'Unclassified backend failure.',
    cause: error,
    stackTrace: stackTrace,
  );
}

SyncErrorKind _kindForCode(String code) {
  switch (code) {
    case 'permission-denied':
    case 'unauthenticated':
      return SyncErrorKind.unauthorized;

    case 'disconnected':
    case 'network-error':
    case 'unavailable':
      return SyncErrorKind.transient;

    // A concurrent write won the race — the record has to be reconciled
    // against what actually landed, which is a conflict, not a retry.
    case 'overridden-by-set':
      return SyncErrorKind.conflict;

    // The transaction gave up after contending too often. Retrying with the
    // engine's backoff is the right answer.
    case 'max-retries':
      return SyncErrorKind.rateLimited;

    case 'expired-token':
    case 'invalid-token':
      return SyncErrorKind.unauthorized;

    case 'write-canceled':
      return SyncErrorKind.permanent;

    default:
      return SyncErrorKind.transient;
  }
}

/// Normalises a child snapshot value into a document map.
///
/// The Realtime Database hands back `Map<Object?, Object?>`, so the keys are
/// re-stringified rather than cast.
Map<String, dynamic>? asDocument(Object? value) {
  if (value is! Map) return null;
  return _normalize(value) as Map<String, dynamic>;
}

/// Re-stringifies map keys at every depth, not just the top level: nested
/// values arrive as `Map<Object?, Object?>` as well.
Object? _normalize(Object? value) {
  if (value is Map) {
    return <String, dynamic>{
      for (final entry in value.entries)
        entry.key.toString(): _normalize(entry.value),
    };
  }
  if (value is List) return value.map(_normalize).toList();
  return value;
}

/// Reads the sync anchor out of a stored child.
///
/// The Realtime Database has no per-record version, so the server timestamp is
/// the only comparison value available.
RemoteAnchor realtimeAnchorFrom(
  Map<String, dynamic> data,
  String updatedAtField,
) {
  final raw = data[updatedAtField];
  if (raw is int) {
    return RemoteAnchor(
      updatedAt: DateTime.fromMillisecondsSinceEpoch(raw, isUtc: true),
    );
  }
  if (raw is String) {
    return RemoteAnchor(updatedAt: DateTime.tryParse(raw)?.toUtc());
  }
  return const RemoteAnchor();
}
