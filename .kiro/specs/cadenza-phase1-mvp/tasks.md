# Implementation Plan: Cadenza Phase 1 MVP

## Overview

Bottom-up implementation of an offline-first local music player for Android and Windows. The build order follows the dependency graph strictly: persistence → repositories → services → scan engine → audio engine → Riverpod providers → shared UI → feature screens → navigation → property-based tests.

## Tasks

- [ ] 1. Flutter project initialisation, pubspec, and folder structure
  - [ ] 1.1 Create the Flutter 3.x project targeting Android and Windows desktop
    - Run `flutter create cadenza --platforms android,windows` and verify both platform folders are present
    - Confirm `flutter run -d windows` and `flutter run -d android` produce the default counter app before any further changes
    - _Requirements: 17_
  - [ ] 1.2 Configure pubspec.yaml with all required dependencies
    - Add `sqflite`, `sqflite_common_ffi`, `path_provider`, `just_audio`, `audio_service`, `on_audio_query`, `flutter_media_metadata`, `id3`, `flutter_riverpod`, `riverpod_annotation`, `go_router`, `file_picker`, `shared_preferences`, `crypto` (for SHA-1 artwork cache key) at pinned versions
    - Add `build_runner`, `riverpod_generator`, `flutter_test`, `test` to dev dependencies
    - Run `flutter pub get` and confirm zero version conflicts
    - _Requirements: 1, 2, 3, 17_
  - [ ] 1.3 Create the full folder structure under `lib/`
    - Create directories: `lib/core/database/`, `lib/core/models/`, `lib/core/repositories/`, `lib/core/services/scan/`, `lib/core/services/`, `lib/core/providers/`, `lib/features/library/`, `lib/features/now_playing/`, `lib/features/queue/`, `lib/features/playlists/`, `lib/features/search/`, `lib/features/settings/`, `lib/shared/widgets/`, `lib/shared/theme/`, `test/unit/`, `test/property/`
    - Create placeholder `.dart` files (empty barrel exports) in each directory so the structure is visible
    - _Requirements: 17_
- [ ] 3. Data models
  - [ ] 3.1 Implement Track, Album, Artist, Playlist, PlaylistTrack, and ScanFolder models
    - Write `lib/core/models/track.dart` with all fields from the schema (`id`, `filePath`, `title`, `artist`, `album`, `albumArtist`, `genre`, `year`, `trackNumber`, `discNumber`, `durationMs`, `fileSize`, `dateAdded`, `dateModified`, `artworkPath`, `isMissing`). Implement `toMap()` and `Track.fromMap()`.
    - Write `lib/core/models/album.dart` (`id`, `name`, `albumArtist`, `year`, `artworkPath`) with `toMap()` / `fromMap()`.
    - Write `lib/core/models/artist.dart` (`id`, `name`) with `toMap()` / `fromMap()`.
    - Write `lib/core/models/playlist.dart` (`Playlist` with `id`, `name`, `dateCreated`, `dateModified`; `PlaylistTrack` with `playlistId`, `trackId`, `position`) with `toMap()` / `fromMap()`.
    - Write `lib/core/models/scan_folder.dart` (`ScanFolder` with `id`, `folderPath`, `lastScanned`) with `toMap()` / `fromMap()`.
    - _Requirements: 1.1, 5.1, 13.1_

  - [ ]* 3.2 Write unit tests for model serialization
    - Round-trip test: `Track.fromMap(track.toMap()) == track` for a fully-populated and a partially-null instance.
    - Same for Album, Playlist, PlaylistTrack, ScanFolder.
    - _Requirements: 5.1, 5.2_


- [ ] 2. Data models
  - [ ] 2.1 Implement `Track` model (`lib/core/models/track.dart`)
    - Define all fields: `id`, `filePath`, `title`, `artist`, `album`, `albumArtist`, `genre`, `year`, `trackNumber`, `discNumber`, `durationMs`, `fileSize`, `dateAdded`, `dateModified`, `artworkPath`, `isMissing`
    - Implement `toMap()` → `Map<String, dynamic>` and `Track.fromMap(Map<String, dynamic>)` factory
    - All nullable fields default to `null`; `isMissing` defaults to `0`
    - _Requirements: 1, 4, 5_
  - [ ] 2.2 Implement `Album`, `Artist`, `Playlist`, `PlaylistTrack`, `ScanFolder` models
    - `Album`: `id`, `name`, `albumArtist`, `year`, `artworkPath` — with `toMap` / `fromMap`
    - `Artist`: `id`, `name` — with `toMap` / `fromMap`
    - `Playlist`: `id`, `name`, `dateCreated`, `dateModified` — with `toMap` / `fromMap`
    - `PlaylistTrack`: `playlistId`, `trackId`, `position` — with `toMap` / `fromMap`
    - `ScanFolder`: `id`, `folderPath`, `lastScanned` — with `toMap` / `fromMap`
    - _Requirements: 1, 13, 18_

- [ ] 3. Database layer
  - [ ] 3.1 Write schema DDL in `lib/core/database/schema.dart`
    - Define `kSchemaStatements` as a `List<String>` containing all `CREATE TABLE IF NOT EXISTS` and `CREATE INDEX IF NOT EXISTS` statements exactly matching the spec schema
    - Tables: `tracks`, `albums`, `artists`, `playlists`, `playlist_tracks`, `scan_folders`
    - Indexes: `idx_tracks_album`, `idx_tracks_artist`, `idx_tracks_title`
    - Foreign keys: `playlist_tracks.playlist_id` → `playlists(id) ON DELETE CASCADE`, `playlist_tracks.track_id` → `tracks(id) ON DELETE CASCADE`
    - _Requirements: 1.1, 1.2, 1.5_
  - [ ] 3.2 Implement `DbProvider` in `lib/core/database/db_provider.dart`
    - Define abstract `DbProvider` with `Future<Database> get database`
    - Implement `AndroidDbProvider` using `sqflite`; implement `WindowsDbProvider` using `sqflite_common_ffi`
    - Static factory `DbProvider.instance` selects implementation at runtime via `Platform.isAndroid`
    - `main.dart` calls `sqfliteFfiInit()` and sets `databaseFactory = databaseFactoryFfi` before `runApp` on Windows — this is the only platform conditional in `main.dart`
    - On first open, execute all `kSchemaStatements` in `onCreate`
    - On failure, throw `DatabaseInitException`; root widget catches and renders blocking error screen before routing to library
    - _Requirements: 1.1, 1.2, 1.3, 1.4, 1.6_
- [ ] 4. TrackRepository
  - [ ] 4.1 Implement TrackRepository
    - Write `lib/core/repositories/track_repository.dart` with the abstract interface and `SqliteTrackRepository` implementation.
    - Implement `getAllTracks({bool includeMissing = false})` — queries `WHERE is_missing = 0` by default, sorted `ORDER BY title COLLATE NOCASE`.
    - Implement `getTrackByPath(String filePath)` — point lookup on the UNIQUE index.
    - Implement `upsertTrack(Track track)` — uses `INSERT OR REPLACE` keyed on `file_path`.
    - Implement `markMissing(String filePath)` — sets `is_missing = 1`.
    - Implement `markFound(String filePath)` — sets `is_missing = 0`.
    - Implement `getScanStats()` — returns a `ScanStats` record with inserted/updated/unchanged counts (counters maintained by the caller scan pass, not derived from DB queries).
    - Implement `search(String query)` — `SELECT * FROM tracks WHERE is_missing = 0 AND (title LIKE '%?%' OR artist LIKE '%?%' OR album LIKE '%?%') COLLATE NOCASE`.
    - _Requirements: 4.1–4.7, 8.2, 14.1, 14.6_

  - [ ]* 4.2 Write unit tests for TrackRepository
    - Test `upsertTrack` inserts a new row and `REPLACE` on same `file_path`.
    - Test `getAllTracks` filters `is_missing = 0` by default and includes missing with flag.
    - Test `markMissing` / `markFound` toggle.
    - Test `search` returns correct subset for a known query.
    - Test `search` with an empty or 1-char query returns empty without a DB call.
    - _Requirements: 4.2, 4.5, 4.7, 14.1, 14.2, 14.3_

- [ ] 5. AlbumRepository and ScanRepository
  - [ ] 5.1 Implement AlbumRepository
    - Write `lib/core/repositories/album_repository.dart` with abstract interface and `SqliteAlbumRepository`.
    - Implement `getAllAlbums()` — sorted `ORDER BY name COLLATE NOCASE`.
    - Implement `getTracksForAlbum(int albumId)` — joins tracks on `album` name.
    - Implement `upsertAlbumFromTrack(Track track)` — `INSERT OR IGNORE INTO albums (name, album_artist, year, artwork_path) VALUES (...)` keyed on `UNIQUE(name, album_artist)`. Only inserts when `track.album != null`.
    - _Requirements: 6.1, 6.2, 6.3, 8.3_

  - [ ] 5.2 Implement ScanRepository
    - Write `lib/core/repositories/scan_repository.dart` with abstract interface and `SqliteScanRepository`.
    - Implement `getScanFolders()` — returns all rows from `scan_folders`.
    - Implement `addScanFolder(String path)` — `INSERT OR IGNORE` with `NULL` `last_scanned`.
    - Implement `removeScanFolder(int id)` — deletes the row (does NOT delete track records).
    - Implement `updateLastScanned(int id, int unixMs)` — updates `last_scanned`.
    - Implement `getAllTrackPathsWithTimestamps()` — returns `Map<String, int?>` of `file_path → date_modified` for all non-missing tracks; used by the scan engine to load the full diff map in one query.
    - _Requirements: 15.2, 15.3, 18.1, 18.2, 18.3_

  - [ ]* 5.3 Write unit tests for AlbumRepository and ScanRepository
    - Test `upsertAlbumFromTrack` is idempotent (double-insert same (name, albumArtist) → still one row).
    - Test `upsertAlbumFromTrack` skips insertion when `track.album == null`.
    - Test `addScanFolder` / `removeScanFolder` lifecycle.
    - Test `getAllTrackPathsWithTimestamps` returns correct map.
    - _Requirements: 6.1, 6.2, 6.3, 18.3_


- [ ] 4. Repositories
  - [ ] 4.1 Implement `TrackRepository` (`lib/core/repositories/track_repository.dart`)
    - Define abstract `TrackRepository` interface with `getAllTracks`, `getTrackByPath`, `upsertTrack`, `markMissing`, `markFound`, `getScanStats`, and `search`
    - Implement `SqliteTrackRepository`: `getAllTracks` filters `WHERE is_missing = 0 ORDER BY title COLLATE NOCASE`; `upsertTrack` uses `INSERT OR REPLACE`; `markMissing` / `markFound` set the `is_missing` flag
    - `search(String query)` executes `SELECT … WHERE is_missing = 0 AND (title LIKE ? OR artist LIKE ? OR album LIKE ?) COLLATE NOCASE` with `'%$query%'` bindings
    - All queries accept an optional `Batch` parameter for use by the scan engine
    - _Requirements: 4.1, 4.2, 4.3, 4.4, 4.5, 4.7, 8.2, 14.1_
  - [ ] 4.2 Implement `AlbumRepository` (`lib/core/repositories/album_repository.dart`)
    - `getAllAlbums()` returns all rows `ORDER BY name COLLATE NOCASE`
    - `getTracksForAlbum(int albumId)` joins `tracks` on `album` field
    - `upsertAlbumFromTrack(Track track)` performs `INSERT OR IGNORE` keyed on `(name, album_artist)` when `track.album != null`
    - _Requirements: 6.1, 8.3_
  - [ ] 4.3 Implement `PlaylistRepository` (`lib/core/repositories/playlist_repository.dart`)
    - Implement `createPlaylist` (checks uniqueness, throws `DuplicateNameException` on conflict), `renamePlaylist`, `deletePlaylist`
    - Implement `addTrackToPlaylist` (appends at max(position)+1), `removeTrackAtPosition` (deletes then `UPDATE … SET position = position - 1 WHERE position > ?` in one transaction), `reorderTracks` (reassigns positions 0..n-1 in one transaction)
    - Implement `getTracksForPlaylist` ordered by `position ASC`
    - _Requirements: 13.1, 13.2, 13.3, 13.4, 13.5, 13.6, 13.7, 13.8, 13.9, 13.10, 13.11_
  - [ ] 4.4 Implement `ScanRepository` (`lib/core/repositories/scan_repository.dart`)
    - `getScanFolders()`, `addScanFolder(String path)`, `removeScanFolder(int id)`, `updateLastScanned(int folderId, int timestampMs)`
    - `addScanFolder` uses `INSERT OR IGNORE` on `folder_path UNIQUE`; records `last_scanned = NULL` on first add
    - _Requirements: 18.1, 18.2, 18.3, 15.2, 15.3_
- [ ] 6. PlaylistRepository
  - [ ] 6.1 Implement PlaylistRepository
    - Write `lib/core/repositories/playlist_repository.dart` with abstract interface and `SqlitePlaylistRepository`.
    - Implement `createPlaylist(String name)` — checks for existing name; throws `DuplicateNameException` if found; inserts with current unix timestamp for `date_created` and `date_modified`.
    - Implement `renamePlaylist(int id, String name)` — checks for name collision with other playlists; throws `DuplicateNameException` on conflict.
    - Implement `deletePlaylist(int id)` — `DELETE FROM playlists WHERE id = ?`; cascade to `playlist_tracks` is handled by the FK `ON DELETE CASCADE`.
    - Implement `getAllPlaylists()` and `getPlaylistById(int id)`.
    - Implement `getTracksForPlaylist(int playlistId)` — joins `playlist_tracks` → `tracks`, ordered by `position`.
    - Implement `addTrackToPlaylist(int playlistId, int trackId)` — appends at `MAX(position) + 1` (or position 0 if empty). Duplicate entries are allowed.
    - Implement `removeTrackAtPosition(int playlistId, int position)` — runs the two-statement transaction: DELETE the row at `position`, then UPDATE `position = position - 1 WHERE position > ?` to close the gap.
    - Implement `reorderTracks(int playlistId, List<int> newTrackIdOrder)` — fetches ordered rows, applies `removeAt`/`insert` in Dart, then batch-updates all positions in a single transaction.
    - _Requirements: 13.1–13.11_

  - [ ]* 6.2 Write unit tests for PlaylistRepository
    - Test `createPlaylist` rejects duplicate names.
    - Test `renamePlaylist` rejects collision with another playlist.
    - Test `addTrackToPlaylist` allows duplicate track entries.
    - Test `removeTrackAtPosition` leaves contiguous positions after removal from the middle.
    - Test `deletePlaylist` cascades and removes all `playlist_tracks` rows.
    - _Requirements: 13.1–13.9_

  - [ ] 6.3 Checkpoint — Ensure all repository and model tests pass
    - Run `flutter test test/` for all unit tests written so far.
    - Ensure all tests pass, ask the user if questions arise.

- [ ] 7. MetadataReaderService and ArtworkCacheService
  - [ ] 7.1 Implement MetadataReaderService
    - Write `lib/core/services/metadata_reader_service.dart` with abstract `MetadataReaderService` interface and `FlutterMediaMetadataReaderService` implementation.
    - Primary path: call `flutter_media_metadata`'s `MetadataRetriever.setDataSource(filePath)` and map all returned fields to a `TrackMetadata` struct.
    - Fallback path: if the primary throws or all fields are null, try the `id3` package.
    - If both fail, log the failure via `debugPrint` and return a `TrackMetadata` with all fields `null`. Do NOT throw or abort the calling scan.
    - NULL policy: absent tags map to `null`; never substitute empty strings or placeholders.
    - _Requirements: 5.1, 5.2, 5.5, 5.6_

  - [ ] 7.2 Implement ArtworkCacheService
    - Write `lib/core/services/artwork_cache_service.dart` with abstract interface and `FileArtworkCacheService` implementation.
    - Compute `sha1(trackFilePath)` as the cache filename. Write `<cacheDir>/<sha1>.jpg` only if the file does not already exist (avoid redundant writes for same-album tracks).
    - Cache directory: `path_provider.getApplicationSupportDirectory()/artwork_cache/`.
    - Return the absolute cache path on success, or `null` when `artworkBytes` is null.
    - _Requirements: 5.3, 5.4_

  - [ ]* 7.3 Write unit tests for MetadataReaderService and ArtworkCacheService
    - Test that when primary metadata reader returns all-null, the fallback is invoked.
    - Test that a fully-tagged fixture file returns all expected non-null fields.
    - Test that a field absent in the file is stored as `null` (not empty string).
    - Test `ArtworkCacheService` does not overwrite an existing cache file on a second call for the same path.
    - _Requirements: 5.2, 5.5_


- [ ] 5. Checkpoint — persistence layer complete
  - Run `flutter test test/unit/` for DB, repository, and model tests.  Ensure all tests pass before proceeding to services. Ask the user if questions arise.

- [ ] 6. MetadataReaderService and ArtworkCacheService
  - [ ] 6.1 Implement `MetadataReaderService` (`lib/core/services/metadata_reader_service.dart`)
    - Define abstract `MetadataReaderService` with `Future<TrackMetadata> readMetadata(String filePath)`
    - Implement `FlutterMediaMetadataReaderService`: primary attempt via `flutter_media_metadata`; on exception or all-null result, fall back to `id3` parser
    - All unreadable / absent fields must be stored as `null` — never empty string or placeholder
    - On total failure, log via `debugPrint` and return an all-null `TrackMetadata`; do not rethrow
    - _Requirements: 5.1, 5.2, 5.3, 5.4, 5.5, 5.6_
  - [ ] 6.2 Implement `ArtworkCacheService` (`lib/core/services/artwork_cache_service.dart`)
    - Define abstract `ArtworkCacheService` with `Future<String?> cacheArtwork(String trackFilePath, Uint8List? artworkBytes)` and `String artworkCacheDir()`
    - Compute cache key as `sha1(trackFilePath)` (hex string); write `<cacheDir>/<sha1>.jpg` only when not already present
    - Cache directory: `path_provider.getApplicationSupportDirectory()/artwork_cache/`
    - Return the file path on success, `null` when `artworkBytes == null`
    - _Requirements: 5.3, 5.4_

- [ ] 7. Scan engine
  - [ ] 7.1 Define `ScanEngine` interface and `ScanProgress` model (`lib/core/services/scan/scan_engine.dart`)
    - Abstract `ScanEngine` with `Stream<ScanProgress> scan(List<ScanFolder> folders)`
    - `ScanProgress` fields: `discovered`, `processed`, `inserted`, `updated`, `unchanged`, `missing`, `isComplete`, optional `error` string
    - _Requirements: 2, 3, 4, 7_
  - [ ] 7.2 Implement `AndroidScanEngine` (`lib/core/services/scan/android_scan_engine.dart`)
    - Query `on_audio_query` for `SongModel` list; do NOT walk the filesystem
    - On Android 13+ request `READ_MEDIA_AUDIO` permission before scan; emit `ScanProgress(error: 'permission_denied')` and return if denied
    - For each `SongModel` apply the incremental diff algorithm (task 7.4 pattern) against `TrackRepository`
    - On zero results emit an appropriate `ScanProgress` with an empty-library message
    - Update `last_scanned` in `ScanRepository` on completion
    - _Requirements: 2.1, 2.2, 2.3, 2.4, 2.5, 17.1_
  - [ ] 7.3 Implement `WindowsScanEngine` (`lib/core/services/scan/windows_scan_engine.dart`)
    - Use `dart:io Directory.list(recursive: true)` to walk each `ScanFolder`; filter extensions `{.mp3, .flac, .aac, .ogg, .m4a, .wav, .opus}` (case-insensitive)
    - On missing folder path log a warning and skip without aborting the rest of the scan
    - Do not import or reference `on_audio_query` or any Android permission API
    - Apply the incremental diff algorithm (task 7.4 pattern) against `TrackRepository`
    - Update `last_scanned` in `ScanRepository` on completion
    - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5, 17.1, 17.4_
  - [ ] 7.4 Implement incremental rescan diff algorithm inside scan engines
    - At scan start load all existing `(filePath, dateModified, id)` tuples into a `Map<String, (int, int)>` (one DB query; O(1) lookups during the walk)
    - For each discovered file: if path absent → `INSERT` via `upsertTrack`; if `diskTs > storedTs` → re-read metadata and `REPLACE`; if timestamps equal → skip (zero writes)
    - Emit a `ScanProgress` event after every 100 files processed
    - After the walk, compute `missingPaths = existingPaths − seen`; call `markMissing` for each in a single transaction
    - If a previously-missing file reappears call `markFound` and update metadata
    - _Requirements: 4.1, 4.2, 4.3, 4.4, 4.5, 4.6, 4.7, 6.1, 6.2_
  - [ ]* 7.5 Write property test — Incremental Rescan Idempotence (Property 1)
    - **Property 1: Incremental Rescan Idempotence**
    - Generate random `(filePath, dateModified, metadata)` tuples; perform a full scan to populate an in-memory test DB; then run rescan twice with no changes to the file set
    - Assert both rescans report `inserted == 0`, `updated == 0`; assert DB row content is identical after each pass
    - Run 100 iterations minimum
    - **Validates: Requirements 4.2, 4.6**
  - [ ]* 7.6 Write property test — Incremental Rescan Diff Correctness (Property 2)
    - **Property 2: Incremental Rescan Diff Correctness**
    - Generate tuples with mix of new / modified / unchanged / missing files; run scan; assert INSERT count == new files, UPDATE count == modified, 0 writes for unchanged, `is_missing = 1` for absent
    - Run 100 iterations minimum
    - **Validates: Requirements 4.1, 4.2, 4.3, 4.4, 4.5**
  - [ ]* 7.7 Write property test — Missing-File Soft Delete No Row Loss (Property 3)
    - **Property 3: Missing-File Soft Delete — No Row Loss**
    - Populate DB with N random tracks; simulate rescan with random non-empty subset absent; assert `count(tracks) >= N` and all absent tracks have `is_missing = 1`
    - Run 100 iterations minimum
    - **Validates: Requirements 4.5, 4.7**
  - [ ]* 7.8 Write property test — Derived Album/Artist Uniqueness (Property 5)
    - **Property 5: Derived Album/Artist Uniqueness**
    - Scan a generated set of tracks with varying album/artist combos; assert `albums.count == count(distinct (album, album_artist) where album != null)`; assert no duplicate `(name, album_artist)` pair in `albums`; assert no duplicate `name` in `artists`
    - Run 100 iterations minimum
    - **Validates: Requirements 6.1, 6.2**
- [ ] 8. ScanEngine — Windows and Android implementations
  - [ ] 8.1 Implement WindowsScanEngine
    - Write `lib/core/services/scan/windows_scan_engine.dart` implementing `ScanEngine`.
    - On `scan(folders)`: for each `ScanFolder`, walk `Directory(folder.folderPath).list(recursive: true)`, filter by extension set `{.mp3, .flac, .aac, .ogg, .m4a, .wav, .opus}` (case-insensitive).
    - If a folder path does not exist, log a warning and skip it without aborting the rest of the scan.
    - For each discovered file, apply the incremental diff algorithm using the pre-loaded `Map<String, int?>` from `ScanRepository.getAllTrackPathsWithTimestamps()`: unchanged → skip; modified → re-read metadata + upsert; new → read metadata + insert.
    - After the file walk, mark as missing any DB tracks whose paths were not seen during the walk.
    - Call `ScanRepository.updateLastScanned` for each successfully walked folder.
    - Emit `ScanProgress` events throughout; emit `ScanProgress(isComplete: true)` at the end.
    - Do NOT reference `on_audio_query` or any Android permission APIs in this file.
    - _Requirements: 3.1–3.5, 4.1–4.7, 6.1, 6.2, 7.1, 17.1, 17.4_

  - [ ] 8.2 Implement AndroidScanEngine
    - Write `lib/core/services/scan/android_scan_engine.dart` implementing `ScanEngine`.
    - Use `on_audio_query` to query songs via `OnAudioQuery().querySongs()`. Do NOT perform any raw filesystem walk.
    - Before scanning on Android 11+, check and request `READ_MEDIA_AUDIO` permission. If denied, emit a `ScanProgress` with `error: 'permission_denied'` and return without scanning.
    - Apply the same incremental diff algorithm as the Windows engine using the pre-loaded path→timestamp map.
    - If the MediaStore query returns zero results, leave the DB unchanged and emit an appropriate error progress event.
    - Emit `ScanProgress(isComplete: true)` on success.
    - Do NOT reference `sqflite_common_ffi` or Windows filesystem APIs in this file.
    - _Requirements: 2.1–2.5, 4.1–4.7, 6.1, 6.2, 17.1_

  - [ ]* 8.3 Write unit tests for ScanEngine incremental diff logic
    - Test that a file with matching `date_modified` produces zero DB writes.
    - Test that a file with a newer `date_modified` produces exactly one UPDATE.
    - Test that a new file (no existing record) produces exactly one INSERT.
    - Test that a WindowsScanEngine skips a missing folder without throwing.
    - Test that files in DB but absent from walk are marked `is_missing = 1`.
    - _Requirements: 3.3, 4.1–4.5, 17.4_


- [ ] 8. AudioPlayerService
  - [ ] 8.1 Define `AudioPlayerService` abstract interface (`lib/core/services/audio_player_service.dart`)
    - Streams: `playbackStateStream`, `currentTrackStream`, `positionStream`, `queueStream`
    - Controls: `playQueue(List<Track>, {int startIndex})`, `playNext(Track)`, `pause()`, `resume()`, `skipToNext()`, `skipToPrevious()`, `seekTo(Duration)`
    - Queue mutation: `reorderQueue(int oldIndex, int newIndex)`, `removeFromQueue(int index)`
    - _Requirements: 9, 10, 11, 12_
  - [ ] 8.2 Implement `DesktopAudioPlayerService` (`lib/core/services/audio_player_service_desktop.dart`)
    - Wrap `just_audio AudioPlayer` directly (no `audio_service` foreground service on Windows)
    - `playQueue` builds `ConcatenatingAudioSource` from `AudioSource.uri(Uri.file(t.filePath))` entries; calls `player.setAudioSource(source, initialIndex: startIndex)` then `player.play()`
    - `skipToPrevious` applies the 3-second rule: seek to `Duration.zero` if `player.position.inSeconds > 3`, else `player.seekToPrevious()`
    - `reorderQueue` / `removeFromQueue` call `ConcatenatingAudioSource.move` / `.removeAt` live without rebuilding the source
    - `playNext` calls `ConcatenatingAudioSource.insert(currentIndex + 1, ...)`
    - _Requirements: 10.1, 10.3, 10.4, 10.5, 10.6, 10.7, 12.1, 12.2, 12.3, 17.2_
  - [ ] 8.3 Implement `AndroidAudioPlayerService` (`lib/core/services/audio_player_service_android.dart`)
    - Extend `BaseAudioHandler` from `audio_service`; wrap the same `just_audio AudioPlayer` inside
    - Override `play`, `pause`, `skipToNext`, `skipToPrevious`, `seek`, `onTaskRemoved`, `onAudioFocusLoss`
    - `skipToPrevious` applies the same 3-second rule as the desktop implementation
    - Surface `MediaItem` from current `Track` to the notification and lock screen
    - On `PlayerException` for an unreadable source, skip to next track and surface a transient error via the stream
    - _Requirements: 9.6, 9.7, 9.8, 10.3, 10.4, 10.5, 11.1, 11.2, 11.3, 11.4, 11.5, 11.6, 11.7, 11.8, 12.1, 12.2, 12.3, 17.2_
  - [ ]* 8.4 Write unit tests for `AudioPlayerService`
    - Test skip-previous 3-second rule: position > 3 s → seeks to zero; position ≤ 3 s → calls seekToPrevious
    - Test `playQueue` builds `ConcatenatingAudioSource` with correct number of children
    - Test `reorderQueue` mutates the source without rebuilding it (verify the source instance is the same object)
    - _Requirements: 9.7, 9.8, 12.3_
- [ ] 9. AudioPlayerService — Desktop and Android implementations
  - [ ] 9.1 Implement DesktopAudioPlayerService
    - Write `lib/core/services/audio_player_service.dart` with the abstract `AudioPlayerService` interface (streams: `playbackStateStream`, `currentTrackStream`, `positionStream`, `queueStream`; methods: `playQueue`, `playNext`, `pause`, `resume`, `skipToNext`, `skipToPrevious`, `seekTo`, `reorderQueue`, `removeFromQueue`).
    - Write `lib/core/services/audio/desktop_audio_player_service.dart` implementing the interface using a bare `just_audio` `AudioPlayer`.
    - `playQueue`: build a `ConcatenatingAudioSource` from `AudioSource.uri(Uri.file(t.filePath), tag: t.toMediaItem())` entries and call `player.setAudioSource(source, initialIndex: startIndex)`.
    - `skipToPrevious`: if `player.position.inSeconds > 3`, call `player.seek(Duration.zero)`; otherwise call `player.seekToPrevious()`.
    - `reorderQueue`: call `concatenatingSource.move(oldIndex, newIndex)`.
    - `removeFromQueue`: call `concatenatingSource.removeAt(index)`.
    - `playNext`: call `concatenatingSource.insert(currentIndex + 1, ...)`.
    - When the queue is empty and a track finishes, stop playback and clear now-playing state.
    - _Requirements: 9.1–9.9, 10.1–10.7, 12.1–12.3_

  - [ ] 9.2 Implement AndroidAudioPlayerService
    - Write `lib/core/services/audio/android_audio_player_service.dart` extending `BaseAudioHandler` (audio_service) and implementing `AudioPlayerService`.
    - Set up the foreground service: override `onTaskRemoved` to gracefully stop; handle `onAudioFocusLoss` to pause.
    - Broadcast `MediaItem` updates (title, artist, artwork URI) on track change so the lock-screen widget and notification shade reflect the current track.
    - All playback and queue logic is identical to `DesktopAudioPlayerService` — delegate to the shared `just_audio` `AudioPlayer` instance.
    - If the audio source throws `PlayerException`, catch it, skip to the next track in the queue, and surface a transient error via the stream.
    - _Requirements: 11.1–11.8, 12.1–12.3_

  - [ ]* 9.3 Write unit tests for AudioPlayerService
    - Test `skipToPrevious` seeks to zero when position > 3 s.
    - Test `skipToPrevious` calls `seekToPrevious` when position ≤ 3 s.
    - Test `playQueue` builds a `ConcatenatingAudioSource` with the correct number of children.
    - Test `reorderQueue` delegates to `concatenatingSource.move`.
    - Test `removeFromQueue` delegates to `concatenatingSource.removeAt`.
    - _Requirements: 9.6, 9.7, 10.3, 10.4, 12.3_

  - [ ] 9.4 Checkpoint — Ensure all service and repository tests pass
    - Run `flutter test test/` for all tests written so far.
    - Ensure all tests pass, ask the user if questions arise.


- [ ] 9. Checkpoint — services complete
  - Run `flutter test test/unit/` and `flutter test test/property/` for all scan and audio tests. Ensure all tests pass before writing providers. Ask the user if questions arise.

- [ ] 10. Riverpod providers
  - [ ] 10.1 Implement core infrastructure providers (`lib/core/providers/providers.dart`)
    - `dbProvider = Provider<DbProvider>(_ => DbProvider.instance)`
    - Repository providers: `trackRepositoryProvider`, `albumRepositoryProvider`, `playlistRepositoryProvider`, `scanRepositoryProvider` — each watches `dbProvider`
    - Service providers (platform-aware): `scanEngineProvider` (`Platform.isAndroid ? AndroidScanEngine : WindowsScanEngine`), `audioPlayerServiceProvider` (`Platform.isAndroid ? AndroidAudioPlayerService : DesktopAudioPlayerService`)
    - _Requirements: 1, 17_
  - [ ] 10.2 Implement library data providers
    - `tracksProvider = FutureProvider<List<Track>>` watching `trackRepositoryProvider`
    - `albumsProvider = FutureProvider<List<Album>>` watching `albumRepositoryProvider`
    - `playlistsProvider = FutureProvider<List<Playlist>>` watching `playlistRepositoryProvider`
    - `scanFoldersProvider = FutureProvider<List<ScanFolder>>` watching `scanRepositoryProvider`
    - _Requirements: 8.2, 8.3, 8.4, 13, 15.1_
  - [ ] 10.3 Implement playback state providers
    - `currentTrackProvider = StreamProvider<Track?>` from `audioPlayerServiceProvider.currentTrackStream`
    - `playbackStateProvider = StreamProvider<PlaybackState>` from `audioPlayerServiceProvider.playbackStateStream`
    - `positionProvider = StreamProvider<Duration>` from `audioPlayerServiceProvider.positionStream`
    - `queueProvider = StreamProvider<List<Track>>` from `audioPlayerServiceProvider.queueStream`
    - _Requirements: 9.1, 9.3, 10.2_
  - [ ] 10.4 Implement `ScanNotifier` and `scanProgressProvider`
    - `ScanState` holds `ScanProgress?`, `isScanning` flag, and optional error string
    - `ScanNotifier.startScan(List<ScanFolder>)` calls `scanEngine.scan(folders)`, streams events into state, and on `isComplete` calls `ref.invalidate(tracksProvider)` and `ref.invalidate(albumsProvider)` to refresh the UI
    - `scanProgressProvider = StateNotifierProvider<ScanNotifier, ScanState>`
    - _Requirements: 7.2, 7.3, 15.7_
  - [ ] 10.5 Implement search providers
    - `searchQueryProvider = StateProvider<String>(_ => '')`
    - `searchResultsProvider = FutureProvider.family<SearchResults, String>` — returns `SearchResults.empty()` when `query.length < 2`; otherwise calls `trackRepositoryProvider.search(query)` and groups results into `{tracks, albums, artists}`
    - _Requirements: 14.1, 14.2, 14.3, 14.4_
  - [ ] 10.6 Implement `ThemeNotifier` and `themeProvider`
    - `ThemeNotifier` reads initial value from `shared_preferences` on construction; persists changes back on toggle
    - `themeProvider = StateNotifierProvider<ThemeNotifier, ThemeMode>`
    - _Requirements: 15.4, 15.5, 15.6_
- [ ] 10. Riverpod providers and app bootstrap
  - [ ] 10.1 Implement all Riverpod providers and wire main.dart
    - Write `lib/core/providers/` with provider definitions for: `dbProvider`, `trackRepositoryProvider`, `albumRepositoryProvider`, `playlistRepositoryProvider`, `scanRepositoryProvider`, `scanEngineProvider` (platform-aware), `audioPlayerServiceProvider` (platform-aware), `tracksProvider`, `albumsProvider`, `playlistsProvider`, `currentTrackProvider`, `playbackStateProvider`, `positionProvider`, `queueProvider`, `scanProgressProvider` (StateNotifierProvider with `ScanNotifier`), `searchQueryProvider`, `searchResultsProvider` (FutureProvider.family), `themeProvider` (StateNotifierProvider, persisted via shared_preferences), `scanFoldersProvider`.
    - `ScanNotifier.completeScan()` must call `ref.invalidate(tracksProvider)` and `ref.invalidate(albumsProvider)` to refresh library UI.
    - Wire `main.dart`: add `ProviderScope` wrapper; add the platform guard for `sqfliteFfiInit` on Windows; catch `DatabaseInitException` at the root and render a blocking error widget.
    - _Requirements: 1.3, 1.6, 15.4, 15.5, 15.6_

  - [ ]* 10.2 Write unit tests for providers
    - Test `scanProgressProvider` transitions from idle → scanning → complete.
    - Test `themeProvider` persists and restores `ThemeMode` across re-creation.
    - Test `searchResultsProvider` returns empty for query length < 2.
    - _Requirements: 14.2, 14.3, 15.5, 15.6_

- [ ] 11. Shared theme and mini-player widget
  - [ ] 11.1 Implement app theme and shared widgets
    - Write `lib/shared/theme/app_theme.dart` defining `ThemeData` for light and dark modes (Material 3, Samsung Music-style: large album art focus, minimal text density).
    - Write `lib/shared/widgets/mini_player_bar.dart` — a persistent bottom widget showing current track title, artist thumbnail, and a play/pause toggle. Visible on all routes except `/now-playing`. Tapping it navigates to `/now-playing` via go_router.
    - Write `lib/shared/widgets/track_list_tile.dart` — a reusable tile showing artwork thumbnail (with placeholder fallback), title, and artist. Used by Songs, Albums detail, Playlist detail, and Search screens.
    - Write `lib/shared/widgets/empty_state.dart` — a reusable widget showing a message and an optional CTA button (used by library empty state, search no-results state).
    - _Requirements: 8.7, 9.2, 14.7, 15.4, 15.5_


- [ ] 11. Shared theme and shared widgets
  - [ ] 11.1 Implement app theme (`lib/shared/theme/app_theme.dart`)
    - Define `AppTheme.light()` and `AppTheme.dark()` returning `ThemeData` with consistent typography, color scheme, and icon theme
    - `CadenzaApp` root widget watches `themeProvider` and passes the resolved `ThemeData` to `MaterialApp.router`
    - _Requirements: 15.4, 15.5_
  - [ ] 11.2 Implement `MiniPlayerBar` widget (`lib/shared/widgets/mini_player_bar.dart`)
    - Watches `currentTrackProvider` and `playbackStateProvider`; hidden when no track is loaded
    - Displays artwork thumbnail, title, artist, and a play/pause `IconButton`
    - Tapping anywhere on the bar navigates to `/now-playing` via `context.go`
    - _Requirements: 9.1, 9.5_
  - [ ] 11.3 Implement `ArtworkWidget` (`lib/shared/widgets/artwork_widget.dart`)
    - Accepts nullable `artworkPath` and an `iconSize` parameter
    - When `artworkPath != null` renders `Image.file(File(artworkPath))` with `errorBuilder` fallback
    - When `artworkPath == null` renders the placeholder asset icon
    - _Requirements: 9.2_
  - [ ] 11.4 Implement `EmptyStateWidget` (`lib/shared/widgets/empty_state_widget.dart`)
    - Accepts `message` and optional `actionLabel` / `onAction` callback
    - Used by library tabs, search, and playlist screens when results are empty
    - _Requirements: 8.7, 14.7, 18.2_

- [ ] 12. Library tabs UI
  - [ ] 12.1 Implement `SongsTab` (`lib/features/library/songs_tab.dart`)
    - Watches `tracksProvider`; renders `AsyncValue.when(data: ..., loading: ..., error: ...)`
    - Data state: `ListView.builder` of all tracks (is_missing == 0) sorted by title; tapping a track calls `audioPlayerServiceProvider.playQueue(allTracks, startIndex: tappedIndex)`
    - Empty state: `EmptyStateWidget` prompting the user to scan
    - _Requirements: 8.1, 8.2, 8.6, 8.7, 10.1_
  - [ ] 12.2 Implement `AlbumsTab` and `AlbumDetailScreen` (`lib/features/library/albums_tab.dart`)
    - `AlbumsTab` watches `albumsProvider`; `ListView.builder` of albums sorted by name
    - Tapping an album navigates to `/library/albums/:id`
    - `AlbumDetailScreen` fetches tracks for that album and renders them in a `ListView.builder`; tapping a track starts playback
    - _Requirements: 8.1, 8.3, 8.6_
  - [ ] 12.3 Implement `ArtistsTab` and `ArtistDetailScreen` (`lib/features/library/artists_tab.dart`)
    - `ArtistsTab` watches an `artistsProvider` (add to providers if absent — `FutureProvider<List<Artist>>` from a new `getAllArtists()` repository method)
    - `ArtistDetailScreen` lists tracks by that artist; tapping a track starts playback
    - _Requirements: 8.1, 8.4, 8.6_
  - [ ] 12.4 Implement `FoldersTab` (`lib/features/library/folders_tab.dart`)
    - Watches `scanFoldersProvider`; lists registered folders and the audio files directly inside each
    - Empty state shows `EmptyStateWidget` linking to Settings to add a folder
    - _Requirements: 8.1, 8.5_
- [ ] 12. Library UI tabs
  - [ ] 12.1 Implement SongsTab
    - Write `lib/features/library/songs_tab.dart`.
    - Watch `tracksProvider`; render a `ListView.builder` (virtualized, always — not conditional on count). Show `empty_state.dart` when the list is empty.
    - Each tile uses `TrackListTile`. Tapping a tile calls `audioPlayerServiceProvider.playQueue(allTracks, startIndex: tappedIndex)`.
    - _Requirements: 8.1, 8.2, 8.6, 8.7, 10.1_

  - [ ] 12.2 Implement AlbumsTab and AlbumDetailScreen
    - Write `lib/features/library/albums_tab.dart` — watches `albumsProvider`, `ListView.builder` grid or list of albums sorted by name.
    - Write `lib/features/library/album_detail_screen.dart` — shows all tracks for the selected album; tapping a track starts playback from that position.
    - _Requirements: 8.1, 8.3, 8.6, 10.1_

  - [ ] 12.3 Implement ArtistsTab and ArtistDetailScreen
    - Write `lib/features/library/artists_tab.dart` — watches a derived artist list, `ListView.builder`.
    - Write `lib/features/library/artist_detail_screen.dart` — lists all tracks for the selected artist.
    - _Requirements: 8.1, 8.4, 8.6, 10.1_

  - [ ] 12.4 Implement FoldersTab
    - Write `lib/features/library/folders_tab.dart` — watches `scanFoldersProvider`; shows registered folders and the audio files directly within each. Empty state prompts user to add a folder in Settings.
    - _Requirements: 8.1, 8.5, 8.7, 18.2_

- [ ] 13. Now Playing screen and Queue screen
  - [ ] 13.1 Implement NowPlayingScreen
    - Write `lib/features/now_playing/now_playing_screen.dart`.
    - Watch `currentTrackProvider` for artwork, title, artist, album. Show placeholder asset when `artworkPath` is null.
    - Watch `positionProvider` for seek bar position (refresh ≤ 500 ms — `positionStream` from just_audio already ticks at ~200 ms).
    - Implement seek bar drag: on drag-end call `audioPlayerServiceProvider.seekTo(position)` within 500 ms.
    - Provide play/pause, skip-next, skip-previous buttons wired to `AudioPlayerService` methods.
    - Provide a button that navigates to `/queue`.
    - _Requirements: 9.1–9.9_

  - [ ] 13.2 Implement QueueScreen
    - Write `lib/features/queue/queue_screen.dart`.
    - Watch `queueProvider`; display ordered list of upcoming tracks (tracks after the currently playing one).
    - Implement `ReorderableListView` for drag-to-reorder, calling `audioPlayerServiceProvider.reorderQueue(oldIndex, newIndex)` on drop.
    - Implement swipe-to-dismiss or a remove button calling `audioPlayerServiceProvider.removeFromQueue(index)`.
    - _Requirements: 10.2–10.4_


- [ ] 13. NowPlayingScreen
  - [ ] 13.1 Implement `NowPlayingScreen` (`lib/features/now_playing/now_playing_screen.dart`)
    - Watches `currentTrackProvider`, `playbackStateProvider`, `positionProvider`, `queueProvider`
    - Displays `ArtworkWidget` (full-size), title, artist, album
    - Seek bar: `Slider` driven by `positionProvider`; `onChanged` calls `audioPlayerServiceProvider.seekTo` — refresh interval ≤ 500 ms guaranteed by `positionStream` cadence
    - Play/pause, skip-next, skip-previous `IconButton`s wired to the service
    - "Queue" button navigates to `/queue`
    - _Requirements: 9.1, 9.2, 9.3, 9.4, 9.5, 9.6, 9.7, 9.8, 9.9_

- [ ] 14. QueueScreen
  - [ ] 14.1 Implement `QueueScreen` (`lib/features/queue/queue_screen.dart`)
    - Watches `queueProvider` and `currentTrackProvider`
    - Renders `ReorderableListView` of upcoming tracks (after current); drag handle triggers `audioPlayerServiceProvider.reorderQueue`
    - Swipe-to-dismiss or delete icon triggers `audioPlayerServiceProvider.removeFromQueue`
    - "Play Next" context action on any library track inserts it via `audioPlayerServiceProvider.playNext`
    - _Requirements: 10.2, 10.3, 10.4, 10.5_
  - [ ]* 14.2 Write property test — Queue Reorder Preserves Multiset (Property 7)
    - **Property 7: Queue Reorder Preserves Multiset**
    - Generate random queue of track IDs and a random permutation; apply via `reorderQueue`; assert `multiset(after) == multiset(before)` — no tracks added or lost
    - Run 100 iterations minimum
    - **Validates: Requirements 10.3**

- [ ] 15. Playlist screens
  - [ ] 15.1 Implement `PlaylistListScreen` (`lib/features/playlists/playlist_list_screen.dart`)
    - Watches `playlistsProvider`; `ListView` of playlists with names and track counts
    - FAB triggers create-playlist dialog; validates uniqueness and displays inline error on `DuplicateNameException`
    - Swipe-to-delete with confirmation; long-press opens rename dialog
    - _Requirements: 13.1, 13.2, 13.3, 13.4, 13.9_
  - [ ] 15.2 Implement `PlaylistDetailScreen` (`lib/features/playlists/playlist_detail_screen.dart`)
    - Fetches tracks via `playlistRepositoryProvider.getTracksForPlaylist(id)` in a `FutureProvider.family`
    - `ReorderableListView` for drag-to-reorder → `playlistRepositoryProvider.reorderTracks`
    - Delete icon per row → `playlistRepositoryProvider.removeTrackAtPosition`
    - "Add Tracks" action navigates to a track picker (modal bottom sheet over `SongsTab`) → `playlistRepositoryProvider.addTrackToPlaylist`
    - Tapping a track calls `audioPlayerServiceProvider.playQueue` starting from that position
    - _Requirements: 13.5, 13.6, 13.7, 13.8, 13.11_
  - [ ]* 15.3 Write property test — Playlist Position Contiguity (Property 6)
    - **Property 6: Playlist Position Contiguity**
    - Generate random sequences of add-track and remove-by-position operations on a playlist; apply them; query `position` values; assert `sorted(positions) == [0, 1, ..., len-1]` (zero-based, no gaps, no duplicates)
    - Run 100 iterations minimum
    - **Validates: Requirements 13.7, 13.8**
- [ ] 14. Playlists screens and Search screen
  - [ ] 14.1 Implement PlaylistListScreen and PlaylistDetailScreen
    - Write `lib/features/playlists/playlist_list_screen.dart` — watches `playlistsProvider`; shows all playlists with a FAB to create new. Create dialog validates for blank name and duplicate (shows inline error on `DuplicateNameException`). Long-press or swipe on a playlist item reveals rename and delete options.
    - Write `lib/features/playlists/playlist_detail_screen.dart` — shows tracks in the playlist ordered by `position`; `ReorderableListView` for drag-to-reorder calling `playlistRepositoryProvider.reorderTracks`. Swipe-to-remove calls `removeTrackAtPosition`. Tapping a track starts playback.
    - _Requirements: 13.1–13.11_

  - [ ] 14.2 Implement SearchScreen
    - Write `lib/features/search/search_screen.dart`.
    - Debounce `searchQueryProvider` updates 300 ms. Watch `searchResultsProvider(query)`.
    - Display results grouped in three `SliverList` sections: Tracks, Albums, Artists — derived from the returned track fields.
    - Show `empty_state.dart` for no results. Do not render sections with zero items.
    - Enforce client-side guard: if `query.length < 2`, show nothing and do not update `searchQueryProvider`.
    - Tapping a result track calls `audioPlayerServiceProvider.playQueue([track], startIndex: 0)`.
    - _Requirements: 14.1–14.7_

- [ ] 15. Settings screen
  - [ ] 15.1 Implement SettingsScreen
    - Write `lib/features/settings/settings_screen.dart`.
    - Watch `scanFoldersProvider`; list registered folders with a remove button per row (calls `scanRepositoryProvider.removeScanFolder`; does NOT delete track records).
    - "Add Folder" button: call `file_picker` (platform-appropriate folder dialog) and call `scanRepositoryProvider.addScanFolder(path)`, then `ref.invalidate(scanFoldersProvider)`.
    - Theme toggle (light/dark `Switch`): calls `themeProvider.toggle()`. Applied immediately app-wide via `MaterialApp.themeMode`.
    - "Scan Now" button: calls `scanProgressProvider.notifier.startScan()`. Show a linear progress indicator while scanning with discovered/processed counts from `ScanProgress`.
    - _Requirements: 15.1–15.7, 18.1–18.3_


- [ ] 16. SearchScreen
  - [ ] 16.1 Implement `SearchScreen` (`lib/features/search/search_screen.dart`)
    - `TextField` writes to `searchQueryProvider` with 300 ms debounce
    - Watches `searchResultsProvider(query)` (returns empty when `query.length < 2`)
    - Results rendered in three `SliverList` sections: Tracks, Albums, Artists — each section hidden when empty
    - Tapping a result track calls `audioPlayerServiceProvider.playQueue`
    - When results are empty for a non-trivial query, show `EmptyStateWidget` with a "no results" message
    - _Requirements: 14.1, 14.2, 14.3, 14.4, 14.5, 14.6, 14.7_
  - [ ]* 16.2 Write property test — Search Substring Correctness (Property 8)
    - **Property 8: Search Substring Correctness**
    - Generate random track sets with diverse titles/artists/albums and random query strings (length ≥ 2); compute expected result set in-process via a pure Dart `contains` filter; assert it equals `SearchService.search(query)` result set
    - Run 100 iterations minimum
    - **Validates: Requirements 14.1**
  - [ ]* 16.3 Write property test — Search Empty/Short Query Guard (Property 9)
    - **Property 9: Search Empty/Short Query Guard**
    - For any query with length 0 or 1 assert `SearchService.search(query)` returns `[]` without executing any SQL
    - Run 100 iterations minimum
    - **Validates: Requirements 14.2, 14.3**

- [ ] 17. SettingsScreen
  - [ ] 17.1 Implement `SettingsScreen` (`lib/features/settings/settings_screen.dart`)
    - Lists registered folders from `scanFoldersProvider`; delete button calls `scanRepositoryProvider.removeScanFolder`
    - "Add Folder" button opens platform folder picker (`file_picker` for both platforms) and calls `scanRepositoryProvider.addScanFolder`
    - Theme toggle `Switch` watches `themeProvider` and calls `themeNotifier.toggle()`
    - "Scan Now" button calls `scanNotifier.startScan(currentFolders)` and navigates to a scan-progress overlay driven by `scanProgressProvider`
    - _Requirements: 15.1, 15.2, 15.3, 15.4, 15.5, 15.6, 15.7, 18.2_

- [ ] 18. Checkpoint — all feature screens complete
  - Run `flutter test` (unit + property). Confirm the Windows build compiles clean (`flutter build windows`). Ask the user if questions arise.

- [ ] 19. go_router navigation wiring
  - [ ] 19.1 Configure `go_router` routes and `ShellRoute` (`lib/core/router/app_router.dart`)
    - Root `ShellRoute` wraps the root scaffold with `BottomNavigationBar` (Library, Search, Playlists, Settings) and the persistent `MiniPlayerBar` above the nav bar
    - Routes: `/library` with `DefaultTabController` hosting `SongsTab`, `AlbumsTab`, `ArtistsTab`, `FoldersTab`; sub-routes `/library/albums/:id` and `/library/artists/:id`
    - Routes: `/search`, `/playlists`, `/playlists/:id`, `/settings`, `/now-playing` (full-screen modal, hides `MiniPlayerBar`), `/queue`
    - Wire `BottomNavigationBar.onTap` to `context.go`; highlight selected tab via `GoRouterState`
    - _Requirements: 8, 9, 10, 13, 14, 15_
  - [ ] 19.2 Implement `main.dart` bootstrap
    - Call `WidgetsFlutterBinding.ensureInitialized()`
    - On Windows/Linux: `sqfliteFfiInit(); databaseFactory = databaseFactoryFfi;` (only platform conditional in `main.dart`)
    - Wrap `CadenzaApp` in `ProviderScope`
    - `CadenzaApp` is a `ConsumerWidget` watching `themeProvider`; uses `MaterialApp.router` with the `go_router` config
    - Catch `DatabaseInitException` in the root widget and render a blocking error screen before routing
    - _Requirements: 1.3, 1.6, 17.2_

- [ ] 20. Final checkpoint — integration complete
  - Run `flutter test` (full suite including property tests). Run `flutter build windows` and `flutter build apk`. Confirm zero errors and zero `on_audio_query` / `sqflite_common_ffi` cross-platform leaks. Ask the user if questions arise.

- [ ] 16. Navigation wiring with go_router
  - [ ] 16.1 Implement root scaffold with go_router and bottom navigation
    - Write `lib/main.dart` (or `lib/app.dart`) defining the `GoRouter` configuration with all routes: `/library` (with `DefaultTabController` for 4 tabs), `/library/albums/:id`, `/library/artists/:id`, `/search`, `/playlists`, `/playlists/:id`, `/settings`, `/now-playing`, `/queue`.
    - Wrap the root `Scaffold` with a `BottomNavigationBar` (Library, Search, Playlists, Settings). Persist bottom nav across tab changes using go_router's `ShellRoute` or a `StatefulShellRoute`.
    - Place `MiniPlayerBar` in the `bottomSheet` slot of the root scaffold; conditionally hide it when the current route is `/now-playing`.
    - `MaterialApp.router` must consume `themeProvider` for `themeMode` so theme toggle applies immediately.
    - _Requirements: 8.1, 9.9, 15.4, 15.5, 16.1, 16.2, 16.3_

  - [ ] 16.2 Checkpoint — Full integration build and smoke test
    - Run `flutter build apk --debug` and `flutter build windows --debug` to confirm clean compilation on both platforms.
    - Verify the Windows build does not reference any Android-specific APIs by scanning import statements in scan/audio files.
    - Ensure all tests pass, ask the user if questions arise.


## Notes

- Tasks marked with `*` are optional and can be skipped for a faster MVP; core correctness properties should be implemented once the corresponding logic is stable
- Every task references specific requirements by number for full traceability
- Build order is strictly bottom-up: DB → models → repositories → services → scan engine → audio service → providers → shared UI → feature screens → router → bootstrap
- The only platform-conditional block allowed in `main.dart` is the `sqfliteFfiInit` guard; all other platform divergence goes through Riverpod provider injection
- `ConcatenatingAudioSource` live-mutation APIs (`move`, `removeAt`, `insert`) must be used for queue edits — no teardown-and-rebuild of the source
- All NULL metadata fields are stored as SQL `NULL`, never empty string or placeholder text
- Artwork is never held in Dart heap after `ArtworkCacheService` writes the file; UI reads via `Image.file` directly from disk

## Task Dependency Graph

```json
{
  "waves": [
    { "id": 0, "tasks": ["1.1", "1.2", "1.3"] },
    { "id": 1, "tasks": ["2.1", "2.2"] },
    { "id": 2, "tasks": ["3.1"] },
    { "id": 3, "tasks": ["3.2"] },
    { "id": 4, "tasks": ["4.1", "4.2", "4.3", "4.4"] },
    { "id": 5, "tasks": ["6.1", "6.2"] },
    { "id": 6, "tasks": ["7.1"] },
    { "id": 7, "tasks": ["7.2", "7.3"] },
    { "id": 8, "tasks": ["7.4"] },
    { "id": 9, "tasks": ["7.5", "7.6", "7.7", "7.8", "8.1"] },
    { "id": 10, "tasks": ["8.2", "8.3"] },
    { "id": 11, "tasks": ["8.4", "10.1"] },
    { "id": 12, "tasks": ["10.2", "10.3", "10.4", "10.5", "10.6"] },
    { "id": 13, "tasks": ["11.1", "11.2", "11.3", "11.4"] },
    { "id": 14, "tasks": ["12.1", "12.2", "12.3", "12.4"] },
    { "id": 15, "tasks": ["13.1", "14.1", "15.1", "16.1", "17.1"] },
    { "id": 16, "tasks": ["13.2", "14.2", "15.2", "16.2", "16.3"] },
    { "id": 17, "tasks": ["15.3"] },
    { "id": 18, "tasks": ["19.1"] },
    { "id": 19, "tasks": ["19.2"] }
  ]
}
```
- [ ] 17. Property-based tests
  - [ ]* 17.1 Write PBT for Property 1 — Incremental Rescan Idempotence
    - Implement a `forAll` helper in `test/helpers/pbt_helpers.dart` that runs a generated test case 100 times.
    - Generate random collections of `(filePath, dateModified, metadata)` tuples. Perform a full scan to populate an in-memory test DB. Run two consecutive rescans with no file changes. Assert both rescans report zero rows written and DB contents are identical before and after each pass.
    - **Property 1: Incremental Rescan Idempotence**
    - **Validates: Requirements 4.2, 4.6**

  - [ ]* 17.2 Write PBT for Property 2 — Incremental Rescan Diff Correctness
    - Generate random sets of `(filePath, diskTs, storedTs)` triples covering: unchanged (diskTs == storedTs), modified (diskTs > storedTs), new (no stored record), and missing (stored but not in scan).
    - Assert: unchanged → 0 writes; modified → exactly 1 UPDATE; new → exactly 1 INSERT; missing → `is_missing = 1`.
    - **Property 2: Incremental Rescan Diff Correctness**
    - **Validates: Requirements 4.1, 4.2, 4.3, 4.4, 4.5**

  - [ ]* 17.3 Write PBT for Property 3 — Missing-File Soft Delete, No Row Loss
    - Populate DB with N random tracks. Simulate rescan where a random non-empty subset is absent. Assert `count(tracks) >= N`, absent tracks have `is_missing = 1`, present tracks have `is_missing = 0`.
    - **Property 3: Missing-File Soft Delete — No Row Loss**
    - **Validates: Requirements 4.5, 4.7**

  - [ ]* 17.4 Write PBT for Property 4 — Metadata Round-Trip Integrity
    - Use a set of pre-constructed test audio files with known embedded tags. For each non-null field in the expected tag set, assert `MetadataReader.read(f).fields[k] == T[k]`. Assert absent fields are stored as `null`, not empty string.
    - **Property 4: Metadata Round-Trip Integrity**
    - **Validates: Requirements 5.1, 5.2**

  - [ ]* 17.5 Write PBT for Property 5 — Derived Album/Artist Uniqueness
    - Generate random track sets with varying album/artist names including duplicates and nulls. Run the scan upsert logic. Assert `albums.count == distinct(name, albumArtist) where album != null`, `artists.count == distinct(artist) where artist != null`. Assert no duplicate (name, albumArtist) pairs in albums.
    - **Property 5: Derived Album/Artist Uniqueness**
    - **Validates: Requirements 6.1, 6.2**

  - [ ]* 17.6 Write PBT for Property 6 — Playlist Position Contiguity
    - Generate random sequences of add-track and remove-by-position operations on a playlist. After each sequence, query `position` values of all remaining `playlist_tracks` rows. Assert `sorted(positions) == [0, 1, ..., len - 1]` with no gaps and no duplicates.
    - **Property 6: Playlist Position Contiguity**
    - **Validates: Requirements 13.7, 13.8**

  - [ ]* 17.7 Write PBT for Property 7 — Queue Reorder Preserves Multiset
    - Generate random queues of track IDs and random permutations. Apply the permutation via `AudioPlayerService.reorderQueue`. Assert `multiset(result) == multiset(original)`.
    - **Property 7: Queue Reorder Preserves Multiset**
    - **Validates: Requirements 10.3**

  - [ ]* 17.8 Write PBT for Property 8 — Search Substring Correctness
    - Generate a random track index and random query strings (length ≥ 2). For each (index, query) pair, compute the expected result set using a pure Dart in-process filter (`title.toLowerCase().contains(q)` || ...). Compare against `SearchService.search(query)`. Assert equality of the two sets.
    - **Property 8: Search Substring Correctness**
    - **Validates: Requirements 14.1**

  - [ ]* 17.9 Write PBT for Property 9 — Search Empty/Short Query Guard
    - For any query `q` where `q.length < 2` (including empty string), assert `SearchService.search(q) == []` and that no SQL statement is issued to the database (use a mock `Database` that fails if any method is called).
    - **Property 9: Search Empty/Short Query Guard**
    - **Validates: Requirements 14.2, 14.3**

  - [ ] 17.10 Final checkpoint — Ensure all tests pass
    - Run `flutter test test/` for the complete suite including all property tests.
    - Ensure all tests pass, ask the user if questions arise.

