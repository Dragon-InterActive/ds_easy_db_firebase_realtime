## 1.1.0

* The sync adapter stamps `updatedAt` with the server time on every push.
  The delta pull depends on it, so it no longer relies on the app writing
  the field with `serverTS`.
* Fixed: collections whose keys are all integers (`"0"`, `"1"`, ...) arrive
  as a `List` from the backend and were reported as empty.
* Nested values are returned as `Map<String, dynamic>` at every depth.
* `watchQuery` keeps a document's own `id` field instead of overwriting it.
* Delta pull skips children without a numeric `updatedAt`; they could block
  the cursor forever.
* A failure to read anchors back after a successful update no longer reports
  the pushed items as failed.

* Added `RealtimeSyncAdapter`, implementing the `ds_sync_contract`
  `SyncRemoteAdapter` interface for use with `ds_easy_db_sync`.
* Added `RealtimeCursor` (keyset delta cursor), `mapRealtimeError`,
  `asDocument` and `realtimeAnchorFrom`.
* Delta pull via `orderByChild` on an indexed `updatedAt` field, continued with
  `startAfter(value, key:)` so children sharing a timestamp are never skipped.
* `pushBatch` uses an atomic multi-path update and reads the server-assigned
  timestamps back as conflict anchors.
* Optional `deletedField` enables remote soft-deletes, which is what makes
  delta deletes possible at all.
* `overridden-by-set` maps to `SyncErrorKind.conflict` (a concurrent write won
  the race, so the record needs reconciling, not retrying); `max-retries` maps
  to `rateLimited`.
* Purely additive — `FirebaseRealtimeDatabase` is unchanged and non-sync usage
  is unaffected.

## 1.0.1

* Added dartdoc comments to public API
* Added example documentation

## 1.0.0

* Initial release
* Firebase Realtime Database integration for DS-EasyDB
* Real-time data synchronization with streaming support
* Low latency updates across all connected clients
* Offline support with automatic sync
* FirebaseOptions parameter for easy initialization
* watch(), watchAll(), and watchQuery() for reactive streams
* Server timestamp support via ServerValue.timestamp
