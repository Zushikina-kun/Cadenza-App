# Requirements Document

## Introduction

Cadenza Phase 1 is an offline-first local music player targeting Android and Windows desktop, built with Flutter 3.x. The application scans user-selected folders for audio files, reads embedded metadata from those files, persists a local track index in SQLite, and provides library browsing, playback, queue management, basic playlist management, and search. All functionality is entirely local — no network requests, cloud sync, or online metadata enrichment are in scope. The goal is a ship-ready MVP that is fast, stable, and persistent across app restarts on both target platforms.

---

## Glossary

- **App**: The Cadenza Flutter application running on Android or Windows.
- **AudioService**: The background audio subsystem wrapping `just_audio` and `audio_service` packages, responsible for playback, queue state, and media notifications.
- **Database**: The local SQLite database managed by `sqflite` (Android) or `sqflite_common_ffi` (Windows) through a unified `db_provider.dart` interface.
- **LibraryView**: The four-tab UI surface displaying Songs, Albums, Artists, and Folders.
- **MetadataReader**: The service that extracts embedded tags (title, artist, album, album artist, genre, year, track number, disc number, duration, artwork) from audio files using `flutter_media_metadata` or the `id3` fallback.
- **NowPlayingScreen**: The full-screen UI showing the current track's artwork, playback controls, and seek bar.
- **Playlist**: A named, ordered, user-created collection of tracks stored entirely in the local Database.
- **Queue**: The ordered sequence of tracks scheduled for playback in the current session, held in memory by the AudioService.
- **ScanEngine**: The service that discovers audio files in user-configured folders, reads their metadata via MetadataReader, and writes or updates the Database. On Android it uses `on_audio_query` (MediaStore); on Windows it uses a direct filesystem walk.
- **ScanFolder**: A filesystem path registered by the user as a root for library scanning, stored in the `scan_folders` Database table.
- **Track**: A single audio file record in the Database, containing all embedded metadata fields and the `file_path` as the unique key.
- **TrackRepository**: The data-access layer for all CRUD operations on tracks, albums, and artists in the Database.
- **PlaylistRepository**: The data-access layer for all CRUD operations on playlists and playlist_tracks in the Database.
- **SearchService**: The in-process substring search over the track index in the Database.
- **Settings**: The user-configurable preferences screen managing ScanFolders and the application theme.
- **Theme**: The visual appearance mode (light or dark) applied app-wide and persisted to local storage.
- **is_missing**: A soft-delete flag (`INTEGER DEFAULT 0`) set to `1` on a Track record when the underlying file is no longer found during a rescan, rather than deleting the row.
- **date_modified**: A unix timestamp stored per Track representing the file system last-modified time, used to detect unchanged files during incremental rescans.
- **Incremental Rescan**: A scan pass that compares `date_modified` values and skips writing to the Database for any file whose timestamp is unchanged since the last scan.
- **Cold Launch**: The first launch of the App after it has been fully terminated (not held in memory by the OS).
- **Warm Start**: An App launch where the Database already contains a previously scanned track index.

---

## Requirements

### Requirement 1: Database Initialization

**User Story:** As a developer, I want the Database to initialize correctly on both Android and Windows, so that all other features have a working persistence layer from first launch.

#### Acceptance Criteria

1. WHEN the App launches on Android, THE Database SHALL initialize using `sqflite` and create all tables (`tracks`, `albums`, `artists`, `playlists`, `playlist_tracks`, `scan_folders`) with the schema defined in the spec if they do not already exist.
2. WHEN the App launches on Windows, THE Database SHALL initialize using `sqflite_common_ffi` and create all tables with the same schema if they do not already exist.
3. THE Database SHALL expose all table operations through a single `db_provider.dart` interface that selects the correct backend (`sqflite` or `sqflite_common_ffi`) at runtime based on the current platform without requiring the caller to specify the backend.
4. WHEN the Database schema already exists on disk, THE Database SHALL open without overwriting or migrating existing data.
5. THE Database SHALL create the indexes `idx_tracks_album`, `idx_tracks_artist`, and `idx_tracks_title` on the `tracks` table at initialization time if they do not already exist.
6. IF the Database file cannot be opened or created, THEN THE App SHALL display an error message stating that the database could not be initialized and SHALL NOT proceed to the library view.

---

### Requirement 2: Library Scan — Android

**User Story:** As a user on Android, I want the App to discover all audio files on my device through the system media index, so that my music library is available without manually selecting every folder.

#### Acceptance Criteria

1. WHEN a library scan is initiated on Android, THE ScanEngine SHALL query audio files using `on_audio_query` (MediaStore API) and SHALL NOT perform a raw filesystem walk of any folder path.
2. WHEN the MediaStore query returns audio file records, THE ScanEngine SHALL pass each record to the MetadataReader and write the resulting Track to the Database.
3. WHEN the App is running on Android 11 or later and the `READ_MEDIA_AUDIO` permission has not been granted, THE ScanEngine SHALL request the permission before initiating the scan and SHALL NOT proceed with the scan if permission is denied.
4. IF the MediaStore query returns zero results, THEN THE ScanEngine SHALL leave the Database unchanged and SHALL display a message to the user indicating that no audio files were found.
5. WHEN a scan completes successfully, THE ScanEngine SHALL update the `last_scanned` timestamp in the `scan_folders` table for each scanned folder.

---

### Requirement 3: Library Scan — Windows

**User Story:** As a user on Windows, I want the App to scan user-selected folders for audio files, so that I can point the player at my local music collection.

#### Acceptance Criteria

1. WHEN a library scan is initiated on Windows, THE ScanEngine SHALL walk the filesystem of each registered ScanFolder recursively and collect all files with audio extensions (`.mp3`, `.flac`, `.aac`, `.ogg`, `.m4a`, `.wav`, `.opus`).
2. WHEN the filesystem walk completes, THE ScanEngine SHALL pass each discovered file to the MetadataReader and write the resulting Track to the Database.
3. WHEN a registered ScanFolder path does not exist on disk at scan time, THE ScanEngine SHALL log a warning and skip that folder without aborting the remainder of the scan.
4. THE ScanEngine SHALL NOT use any Android-specific permission code paths (e.g., `on_audio_query`, `READ_MEDIA_AUDIO` requests) when running on Windows.
5. WHEN a scan completes successfully on Windows, THE ScanEngine SHALL update the `last_scanned` timestamp for each successfully walked ScanFolder.

---

### Requirement 4: Incremental Rescan

**User Story:** As a user, I want the App to rescan my library quickly when I add or remove a few files, so that the library updates without a full re-read of every track.

#### Acceptance Criteria

1. WHEN a rescan is initiated, THE ScanEngine SHALL compare the `date_modified` filesystem timestamp of each discovered file against the `date_modified` value stored in the corresponding Track record.
2. WHEN a file's `date_modified` timestamp matches the stored value, THE ScanEngine SHALL skip writing any Database row for that file.
3. WHEN a file's `date_modified` timestamp is newer than the stored value, THE ScanEngine SHALL re-read metadata from the file and update the corresponding Track row in the Database.
4. WHEN a file is newly discovered (no matching Track record exists by `file_path`), THE ScanEngine SHALL insert a new Track row.
5. WHEN a file that was previously scanned is no longer found on disk during a rescan, THE ScanEngine SHALL set `is_missing = 1` on the corresponding Track row and SHALL NOT delete the row.
6. WHEN a rescan of a library with zero file changes completes, THE TrackRepository SHALL report that zero rows were inserted, updated, or deleted.
7. WHEN a previously missing Track (where `is_missing = 1`) is found again on disk during a rescan, THE ScanEngine SHALL set `is_missing = 0` and update the Track row with current metadata.

---

### Requirement 5: Metadata Reading

**User Story:** As a user, I want the player to display accurate track information from my files' embedded tags, so that my library is organized correctly without manual editing.

#### Acceptance Criteria

1. WHEN the MetadataReader processes an audio file, THE MetadataReader SHALL attempt to read the following fields from embedded tags: title, artist, album, album artist, genre, year, track number, disc number, duration in milliseconds, and embedded artwork.
2. WHEN an embedded tag field is absent or unreadable, THE MetadataReader SHALL store a `NULL` value for that field in the Track record rather than substituting a default or placeholder string.
3. WHEN embedded artwork is present in an audio file, THE MetadataReader SHALL extract the artwork and write it to a cached file path, storing that path in the `artwork_path` field of the Track record.
4. WHEN embedded artwork is absent, THE MetadataReader SHALL store `NULL` in the `artwork_path` field.
5. THE MetadataReader SHALL use `flutter_media_metadata` as the primary tag-reading library and SHALL fall back to the `id3` library if `flutter_media_metadata` fails to parse a given file.
6. WHEN metadata reading fails for a file with an unsupported format, THE MetadataReader SHALL log the failure and skip that file without aborting the overall scan.

---

### Requirement 6: Derived Album and Artist Records

**User Story:** As a developer, I want album and artist records to be derived automatically from track metadata during scans, so that the Albums and Artists views are always consistent with the track index.

#### Acceptance Criteria

1. WHEN the ScanEngine writes a Track record that contains a non-NULL `album` value, THE ScanEngine SHALL perform an `INSERT OR IGNORE` into the `albums` table keyed on `(name, album_artist)`.
2. WHEN the ScanEngine writes a Track record that contains a non-NULL `artist` value, THE ScanEngine SHALL perform an `INSERT OR IGNORE` into the `artists` table keyed on `name`.
3. THE ScanEngine SHALL NOT maintain album or artist records by any mechanism other than derivation from track rows during a scan pass.
4. WHEN all tracks belonging to an album are marked `is_missing = 1`, THE corresponding album record SHALL remain in the Database and SHALL NOT be deleted.

---

### Requirement 7: Scan Performance

**User Story:** As a user, I want the initial library scan to complete quickly even for large collections, so that I can start listening without a long wait.

#### Acceptance Criteria

1. WHEN the ScanEngine scans a library of 5,000 audio files on a machine with a Ryzen 5 5600 processor, THE ScanEngine SHALL complete the full scan in under 30 seconds.
2. WHEN the App performs a Warm Start (Database already populated), THE App SHALL display the library list within 2 seconds of launch.
3. WHEN a rescan is triggered on a library where no files have changed, THE ScanEngine SHALL complete the rescan without writing any Database rows and SHALL finish in a time proportional to the number of files checked, not the number of tracks in the Database.

---

### Requirement 8: Library Views

**User Story:** As a user, I want to browse my music collection by song, album, artist, and folder, so that I can find tracks using whichever organizational method suits me.

#### Acceptance Criteria

1. THE LibraryView SHALL present four tabs: Songs, Albums, Artists, and Folders.
2. WHEN the Songs tab is active, THE LibraryView SHALL display a flat, scrollable list of all Track records in the Database where `is_missing = 0`, sorted alphabetically by title.
3. WHEN the Albums tab is active, THE LibraryView SHALL display a flat, scrollable list of all album records derived from the Database, sorted alphabetically by album name.
4. WHEN the Artists tab is active, THE LibraryView SHALL display a flat, scrollable list of all artist records derived from the Database, sorted alphabetically by artist name.
5. WHEN the Folders tab is active, THE LibraryView SHALL display the registered ScanFolders and the audio files discovered directly within each folder.
6. WHEN a list in any tab contains more than 100 items, THE LibraryView SHALL render the list using a virtualized `ListView.builder` to avoid building all items at once.
7. WHEN no tracks are present in the Database, THE LibraryView SHALL display an empty-state message prompting the user to scan a folder.

---

### Requirement 9: Now Playing Screen

**User Story:** As a user, I want a full-screen Now Playing view showing what is currently playing, so that I can see track details and control playback easily.

#### Acceptance Criteria

1. WHEN a track begins playing, THE NowPlayingScreen SHALL display the track's embedded artwork, title, artist, and album.
2. WHEN embedded artwork is unavailable for the current track, THE NowPlayingScreen SHALL display a generic placeholder artwork image.
3. THE NowPlayingScreen SHALL display a seek bar that reflects the current playback position in real time, updated at an interval of no greater than 500 milliseconds.
4. WHEN the user drags the seek bar to a new position, THE AudioService SHALL seek to that position within 500 milliseconds of the gesture completing.
5. THE NowPlayingScreen SHALL provide play, pause, skip-to-next-track, and skip-to-previous-track controls.
6. WHEN the skip-to-next-track control is activated and the Queue contains a subsequent track, THE AudioService SHALL begin playing the next track without an audible gap exceeding 200 milliseconds.
7. WHEN the skip-to-previous-track control is activated and playback position is greater than 3 seconds into the track, THE AudioService SHALL seek to the beginning of the current track rather than skipping to the previous track.
8. WHEN the skip-to-previous-track control is activated and playback position is 3 seconds or less into the track, THE AudioService SHALL begin playing the previous track in the Queue.
9. THE NowPlayingScreen SHALL provide a control to navigate to the Queue screen.

---

### Requirement 10: Queue Management

**User Story:** As a user, I want to view and manage the upcoming playback queue, so that I can control what plays next without interrupting the current track.

#### Acceptance Criteria

1. WHEN a track is selected for playback from any library view, THE AudioService SHALL replace the current Queue with a new queue containing that track and all subsequent tracks in the same list, starting playback from the selected track.
2. THE Queue screen SHALL display the ordered list of all tracks scheduled for playback after the currently playing track.
3. WHEN the user reorders tracks in the Queue screen, THE AudioService SHALL update the Queue to reflect the new order immediately.
4. WHEN the user removes a track from the Queue screen, THE AudioService SHALL remove that track from the Queue immediately.
5. WHEN the user selects "Play Next" on any track, THE AudioService SHALL insert that track immediately after the currently playing track in the Queue.
6. WHEN the Queue is empty and a track finishes playing, THE AudioService SHALL stop playback and clear the now-playing state.
7. WHEN the last track in the Queue finishes playing, THE AudioService SHALL stop playback.

---

### Requirement 11: Background Playback and Media Notifications — Android

**User Story:** As a user on Android, I want music to continue playing when I lock my phone or switch apps, so that I don't have to keep Cadenza in the foreground.

#### Acceptance Criteria

1. WHEN the App is moved to the background on Android, THE AudioService SHALL continue playback without interruption.
2. WHEN the device screen is locked while a track is playing on Android, THE AudioService SHALL continue playback without interruption.
3. WHILE a track is playing on Android, THE AudioService SHALL display a media notification in the notification shade showing the track title, artist, artwork, and transport controls (play/pause, skip next, skip previous).
4. WHEN the user taps the play/pause control in the media notification on Android, THE AudioService SHALL toggle the playback state.
5. WHEN the user taps the skip-next control in the media notification on Android, THE AudioService SHALL advance to the next track in the Queue.
6. WHEN the user taps the skip-previous control in the media notification on Android, THE AudioService SHALL apply the same skip-previous logic as the NowPlayingScreen controls.
7. WHILE a track is playing on Android, THE AudioService SHALL display the track title, artist, and artwork on the lock screen media control widget.
8. IF the Android OS terminates the audio service process due to memory pressure, THEN THE AudioService SHALL attempt to restart playback from the last known position when the App is foregrounded again.

---

### Requirement 12: Gapless Playback

**User Story:** As a user, I want consecutive tracks to play without an audible gap between them, so that albums and mixes sound continuous.

#### Acceptance Criteria

1. WHEN one track ends and the next track in the Queue begins on the same platform session, THE AudioService SHALL transition between the two tracks with no audible gap exceeding 200 milliseconds.
2. WHEN playing a queue of 20 consecutive tracks from start to finish, THE AudioService SHALL complete all 20 transitions without an audible gap or a crash.
3. THE AudioService SHALL use `just_audio`'s seamless queue mechanism (ConcatenatingAudioSource) to enable gapless transitions and SHALL NOT implement manual track sequencing that relies on observing a stream-end event before loading the next track.

---

### Requirement 13: Playlists

**User Story:** As a user, I want to create and manage playlists of my local tracks, so that I can group songs for different moods or occasions.

#### Acceptance Criteria

1. THE PlaylistRepository SHALL allow the user to create a new Playlist with a unique name.
2. WHEN the user creates a Playlist with a name that already exists, THE PlaylistRepository SHALL return an error and SHALL NOT create a duplicate Playlist record.
3. THE PlaylistRepository SHALL allow the user to rename an existing Playlist to a new name.
4. WHEN the user renames a Playlist to a name already used by another Playlist, THE PlaylistRepository SHALL return an error and SHALL NOT perform the rename.
5. THE PlaylistRepository SHALL allow the user to add a Track to a Playlist, appending it at the end of the `position` order.
6. WHEN a Track is added to a Playlist that already contains that Track, THE PlaylistRepository SHALL add a duplicate entry (a track may appear multiple times in a playlist).
7. THE PlaylistRepository SHALL allow the user to remove a specific Track entry from a Playlist by its `position` index.
8. WHEN a Track is removed from the middle of a Playlist, THE PlaylistRepository SHALL update the `position` values of all subsequent entries to remain contiguous.
9. THE PlaylistRepository SHALL allow the user to delete a Playlist, which SHALL cascade-delete all `playlist_tracks` rows for that Playlist.
10. WHEN a Track is deleted from the Database (or marked `is_missing = 1`), THE playlist_tracks rows referencing that Track SHALL cascade-delete per the foreign key constraint.
11. THE Playlist detail screen SHALL allow the user to reorder tracks by dragging, updating stored `position` values atomically.

---

### Requirement 14: Search

**User Story:** As a user, I want to search my library by typing part of a track title, artist name, or album name, so that I can find specific songs quickly without scrolling.

#### Acceptance Criteria

1. WHEN the user submits a search query, THE SearchService SHALL query the Database for Track records where `title`, `artist`, or `album` contains the query string as a case-insensitive substring.
2. WHEN the search query is an empty string, THE SearchService SHALL return no results and SHALL NOT execute a database query.
3. WHEN the search query contains fewer than 2 characters, THE SearchService SHALL return no results.
4. WHEN the SearchService returns results, THE App SHALL display them grouped by match category (Tracks, Albums, Artists) in the search results view.
5. WHEN the user taps a search result track, THE AudioService SHALL begin playing that track.
6. THE SearchService SHALL use SQL `LIKE '%query%'` matching and SHALL NOT implement fuzzy matching or phonetic matching in Phase 1.
7. WHEN a search query produces no matching results, THE App SHALL display a no-results message rather than an empty screen.

---

### Requirement 15: Basic Settings

**User Story:** As a user, I want a settings screen where I can manage my scan folders and toggle the app theme, so that I can customize the player to my environment.

#### Acceptance Criteria

1. THE Settings screen SHALL display the list of currently registered ScanFolders.
2. WHEN the user taps "Add Folder" in Settings, THE App SHALL present a system folder-picker dialog appropriate for the current platform (Android folder picker or Windows directory dialog) and SHALL add the selected path to the `scan_folders` table.
3. WHEN the user removes a ScanFolder from Settings, THE App SHALL delete the corresponding row from the `scan_folders` table and SHALL NOT automatically delete any Track records associated with that folder.
4. THE Settings screen SHALL display a theme toggle control allowing the user to switch between light mode and dark mode.
5. WHEN the user toggles the theme, THE App SHALL apply the new Theme to all screens immediately without requiring a restart.
6. WHEN the App is relaunched, THE App SHALL restore the previously selected Theme from local persistent storage.
7. THE Settings screen SHALL provide a "Scan Now" button that triggers a full scan of all registered ScanFolders.

---

### Requirement 16: Data Persistence

**User Story:** As a user, I want my library, playlists, and settings to persist across app restarts and force-closes, so that I never lose my data unexpectedly.

#### Acceptance Criteria

1. WHEN the App is force-closed and relaunched, THE Database SHALL contain all Track records, Playlist records, and ScanFolder records that existed before the force-close.
2. WHEN the App is relaunched after a force-close, THE App SHALL NOT initiate an automatic rescan unless the user explicitly triggers one.
3. WHEN the App is relaunched after a force-close, THE App SHALL reach the library view displaying the previously scanned tracks within 2 seconds.

---

### Requirement 17: Cross-Platform Isolation

**User Story:** As a developer, I want the Windows build to work without any Android-specific code paths, so that platform-specific code does not cause crashes or build failures on the wrong platform.

#### Acceptance Criteria

1. WHEN the App is compiled and run on Windows, THE App SHALL NOT invoke `on_audio_query`, `READ_MEDIA_AUDIO`, or any other Android-specific API.
2. WHEN the App is compiled and run on Android, THE App SHALL NOT invoke `sqflite_common_ffi` initialization paths intended for desktop.
3. THE App SHALL use compile-time or runtime platform guards (e.g., `Platform.isAndroid`, `Platform.isWindows`) to select platform-specific implementations at every point where Android and Windows behavior differs.
4. THE App SHALL produce a clean build on Windows without any Android-specific compile errors or warnings related to scoped storage permissions.

---

### Requirement 18: Scan Folder Management

**User Story:** As a developer, I want scan folder records to be the authoritative list of locations the ScanEngine operates on, so that the scan scope is always user-controlled and explicit.

#### Acceptance Criteria

1. THE ScanEngine SHALL only scan file paths that are reachable under a registered ScanFolder entry in the `scan_folders` table.
2. WHEN no ScanFolders are registered, THE ScanEngine SHALL perform no filesystem operations and SHALL display a prompt to the user to add a folder in Settings.
3. WHEN a ScanFolder is added, THE App SHALL record the folder path and a NULL `last_scanned` timestamp until the first scan of that folder completes.

---

## Correctness Properties

The following properties are suitable for property-based testing. Each targets logic internal to the Cadenza codebase (not external package behavior) and varies meaningfully with input.

### Property 1: Incremental Rescan Idempotence

**Requirement reference:** Requirement 4.6

The incremental rescan algorithm is idempotent: running the rescan pass twice on a library where no files change between passes produces the same Database state and writes zero rows on both passes.

**Formal property:**
For any database state `D` and any set of files `F` where all `date_modified` values in `F` match the stored values in `D`:
```
rescan(rescan(D, F), F) == rescan(D, F)   AND   writes(rescan(D, F)) == 0
```

**Testing approach:** Property-based test with generated file sets. Generate a random collection of `(file_path, date_modified, metadata)` tuples, perform a full scan to populate the Database, then perform two consecutive rescans with no changes to `F`. Assert that both rescans report zero rows written and that the Database contents are identical before and after each rescan.

---

### Property 2: Metadata Round-Trip Integrity

**Requirement reference:** Requirement 5

The MetadataReader produces Track records whose fields contain exactly the tag values embedded in the source file — no field is silently dropped, truncated, or transformed.

**Formal property:**
For any audio file `f` with embedded tags `T`:
```
MetadataReader.read(f).fields == T.fields   (for all non-NULL fields in T)
```

**Testing approach:** Property-based test using a set of pre-constructed test audio files with known embedded tags (title, artist, album, year, track number, disc number). Assert that for every non-NULL field in the expected tag set, the MetadataReader returns exactly that value. Also assert that fields not present in the file are stored as `NULL` rather than empty string or placeholder.

---

### Property 3: Playlist Position Contiguity After Removal

**Requirement reference:** Requirement 13.8

After any sequence of add and remove operations on a Playlist, the `position` values of remaining entries form a contiguous, zero-based (or one-based) integer sequence with no gaps.

**Formal property:**
For any Playlist `P` and any sequence of add/remove operations `ops`:
```
let positions = sorted(apply(ops, P).positions)
positions == [0, 1, 2, ..., len(positions) - 1]
```

**Testing approach:** Property-based test that generates random sequences of add-track and remove-track operations, applies them to a Playlist, then queries the `position` values of all remaining `playlist_tracks` rows. Assert that the sorted position list is always contiguous with no duplicates and no gaps.

---

### Property 4: Search Substring Correctness

**Requirement reference:** Requirement 14.1

The SearchService returns exactly the set of tracks whose title, artist, or album contains the query as a case-insensitive substring — no more, no fewer.

**Formal property:**
For any query string `q` and any set of tracks `T` in the Database:
```
SearchService.search(q) == { t ∈ T | contains_ci(t.title, q) OR contains_ci(t.artist, q) OR contains_ci(t.album, q) }
```
where `contains_ci(s, q)` is case-insensitive substring containment.

**Testing approach:** Property-based test that generates a random track index with diverse titles/artists/albums and random query strings. For each generated (index, query) pair, independently compute the expected result set using a reference in-process filter, then compare against the SearchService result. Assert that the two sets are always equal.

---

### Property 5: Queue Ordering Invariant After Reorder

**Requirement reference:** Requirement 10.3

After any reorder operation on the Queue, the set of tracks in the Queue is unchanged — only their order changes. No tracks are added or lost.

**Formal property:**
For any Queue state `Q` and any permutation `σ`:
```
multiset(reorder(Q, σ)) == multiset(Q)
```

**Testing approach:** Property-based test that generates a random queue of track references and a random permutation. Apply the permutation to the queue via the reorder operation. Assert that the resulting queue contains exactly the same multiset of track identifiers as the original queue.

---

### Property 6: Missing-File Soft Delete — No Row Loss

**Requirement reference:** Requirement 4.5

When files disappear between scans, the number of Track rows in the Database never decreases — the `is_missing` flag is set instead of rows being deleted.

**Formal property:**
For any database state `D` with `N` tracks and any rescan where a subset of files are missing:
```
count(rows after rescan) >= N
```

**Testing approach:** Property-based test that populates the Database with a random set of tracks, then simulates a rescan where a random non-empty subset of files is absent. Assert that the total row count in the `tracks` table is unchanged and that the absent tracks have `is_missing = 1`.
