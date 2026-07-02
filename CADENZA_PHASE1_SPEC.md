# CADENZA — PHASE 1 BUILD SPEC (MVP)
**Scope:** Android + Windows, offline-first local music player.
**Not in this doc:** Sync, plugins, streaming connectors, handheld editions, AI tools — all Phase 3/4, deliberately excluded so Kiro doesn't scope-creep the MVP.

---

## 0. STACK DECISION (LOCKED)

| Layer | Choice | Why |
|---|---|---|
| Framework | **Flutter 3.x** | Single codebase for Android + Windows desktop; you already know this stack from SmartSpend |
| Local DB | **sqflite** (Android) — see note below for Windows | Matches SmartSpend, zero new learning curve |
| Audio engine | **just_audio** + **audio_service** (background playback, media notifications) | Most mature Flutter audio stack; gapless supported via `just_audio`'s clipping/seamless queue, not bit-perfect but good enough for MVP |
| File scanning | **MediaStore** via `on_audio_query` plugin (Android) / direct filesystem walk (Windows) | Avoids raw folder scanning on Android 11+ scoped storage — this is mandatory, not optional |
| Metadata read (local tags) | `flutter_media_metadata` or `id3` (fallback) | Reads embedded tags before any online enrichment |
| State management | **Riverpod** (or Provider if you want zero new learning curve from SmartSpend) | Your call — flag which one to Kiro explicitly |

**Windows DB note:** `sqflite` doesn't support Windows natively. Use `sqflite_common_ffi` for desktop, same SQL schema, different bootstrap. Tell Kiro this explicitly or it'll try to run mobile sqflite on Windows and fail silently on first launch.

**Online metadata (MusicBrainz/Discogs/Last.fm/AcoustID) is OUT of Phase 1 entirely.** Local tag reading only. This directly resolves the offline-first contradiction flagged earlier — nothing in MVP requires network.

---

## 1. PHASE 1 FEATURE SCOPE (and only this)

### In scope
- Folder/library scan → build local track index (SQLite)
- Read embedded metadata (title, artist, album, album artist, genre, year, track#, disc#, duration, embedded artwork)
- Library views: **Songs / Albums / Artists / Folders** (4 tabs, flat lists, no smart grouping yet)
- Now Playing screen (art, controls, seek bar, queue access)
- Queue (add, reorder, remove, play next)
- Basic playlists (create, add/remove tracks, rename, delete) — local only, no smart playlists
- Search (title/artist/album, simple substring match — fuzzy search is Phase 2)
- Background playback + media notification controls (lock screen / notification shade)
- Basic settings screen (scan folders, theme toggle)

### Explicitly OUT of Phase 1 (say this to Kiro so it doesn't build them unprompted)
- MusicBrainz/Discogs/Last.fm/AcoustID integration
- Smart playlists, duplicate detection, library health score
- Sync (Android ↔ Windows)
- Plugin system
- Crossfade, ReplayGain, EQ, pitch control
- Fuzzy/lyrics search
- Handheld editions

---

## 2. DATA MODEL (SQLite schema, Phase 1 only)

```sql
CREATE TABLE tracks (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  file_path TEXT NOT NULL UNIQUE,
  title TEXT,
  artist TEXT,
  album TEXT,
  album_artist TEXT,
  genre TEXT,
  year INTEGER,
  track_number INTEGER,
  disc_number INTEGER,
  duration_ms INTEGER,
  file_size INTEGER,
  date_added INTEGER,       -- unix timestamp
  date_modified INTEGER,    -- for incremental rescan diffing
  artwork_path TEXT,        -- cached extracted artwork, nullable
  is_missing INTEGER DEFAULT 0  -- soft-delete flag if file no longer found on rescan
);

CREATE TABLE albums (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  album_artist TEXT,
  year INTEGER,
  artwork_path TEXT,
  UNIQUE(name, album_artist)
);

CREATE TABLE artists (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL UNIQUE
);

CREATE TABLE playlists (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  date_created INTEGER,
  date_modified INTEGER
);

CREATE TABLE playlist_tracks (
  playlist_id INTEGER NOT NULL,
  track_id INTEGER NOT NULL,
  position INTEGER NOT NULL,
  FOREIGN KEY (playlist_id) REFERENCES playlists(id) ON DELETE CASCADE,
  FOREIGN KEY (track_id) REFERENCES tracks(id) ON DELETE CASCADE
);

CREATE TABLE scan_folders (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  folder_path TEXT NOT NULL UNIQUE,
  last_scanned INTEGER
);

-- Indexes for scroll/search performance at scale
CREATE INDEX idx_tracks_album ON tracks(album);
CREATE INDEX idx_tracks_artist ON tracks(artist);
CREATE INDEX idx_tracks_title ON tracks(title);
```

Notes for Kiro:
- `albums` and `artists` tables are **derived/denormalized** from `tracks` on scan — don't hand-maintain them separately, rebuild via `INSERT OR IGNORE` during the scan pass keyed on the unique constraints.
- `date_modified` + `is_missing` exist specifically to support incremental rescans (Phase 1 requirement, not Phase 2) — full rescan every launch is a perf killer at 10k+ tracks.

---

## 3. FLUTTER PROJECT STRUCTURE

```
cadenza/
├── lib/
│   ├── main.dart
│   ├── core/
│   │   ├── database/
│   │   │   ├── db_provider.dart          # sqflite (mobile) + sqflite_common_ffi (desktop) bootstrap
│   │   │   └── schema.dart
│   │   ├── models/
│   │   │   ├── track.dart
│   │   │   ├── album.dart
│   │   │   ├── artist.dart
│   │   │   └── playlist.dart
│   │   ├── repositories/
│   │   │   ├── track_repository.dart
│   │   │   ├── album_repository.dart
│   │   │   ├── playlist_repository.dart
│   │   │   └── scan_repository.dart      # folder scan + incremental diff logic
│   │   └── services/
│   │       ├── audio_player_service.dart # wraps just_audio + audio_service
│   │       ├── metadata_reader_service.dart
│   │       └── artwork_cache_service.dart
│   ├── features/
│   │   ├── library/
│   │   │   ├── songs_tab.dart
│   │   │   ├── albums_tab.dart
│   │   │   ├── artists_tab.dart
│   │   │   └── folders_tab.dart
│   │   ├── now_playing/
│   │   │   └── now_playing_screen.dart
│   │   ├── queue/
│   │   │   └── queue_screen.dart
│   │   ├── playlists/
│   │   │   ├── playlist_list_screen.dart
│   │   │   └── playlist_detail_screen.dart
│   │   ├── search/
│   │   │   └── search_screen.dart
│   │   └── settings/
│   │       └── settings_screen.dart
│   └── shared/
│       ├── widgets/
│       └── theme/
├── pubspec.yaml
└── platform-specific folders (android/, windows/) — Flutter default, don't hand-edit unless needed
```

Kiro should build this bottom-up: **db schema → repositories → scan service → audio service → UI tabs**, in that order. Building UI before the scan/repository layer works is the most common cause of throwaway rework.

---

## 4. DEFINITION OF DONE — PHASE 1 MVP

Ship-ready when all of the following hold:
- Scanning 5,000 local tracks completes in under 30 seconds on your Ryzen 5 5600 desktop build
- Cold app launch to visible library list is under 2 seconds with a pre-scanned DB (warm start — not counting first-ever scan)
- Rescanning an already-scanned library with zero file changes touches zero rows (incremental diff proven, not just claimed)
- Playback survives app backgrounding and screen lock on Android with working notification controls
- No audible gap or crash between consecutive tracks in a 20-track queue
- Library survives force-close/reopen without re-scanning or losing playlists
- Windows build launches and scans a local folder without needing Android-specific permissions code paths

---

## 5. KIRO PROMPT PACK (copy-paste ready)

**Prompt 1 — Project init**
```
Set up a new Flutter 3.x project called "cadenza" targeting Android and Windows desktop.
Add dependencies: sqflite, sqflite_common_ffi, path_provider, just_audio, audio_service,
on_audio_query, flutter_media_metadata, riverpod (or provider — confirm which).
Create the folder structure exactly as specified in CADENZA_PHASE1_SPEC.md section 3.
Do not add any packages related to networking, MusicBrainz, or cloud sync — this is an
offline-only Phase 1 build.
```

**Prompt 2 — Database layer**
```
Implement the SQLite schema from CADENZA_PHASE1_SPEC.md section 2 using sqflite for
Android and sqflite_common_ffi for Windows, behind a single db_provider.dart that picks
the right backend at runtime based on platform. Implement track_repository.dart,
album_repository.dart, and playlist_repository.dart with CRUD methods matching the
schema. Albums and artists tables must be derived from tracks during scan, not
hand-maintained.
```

**Prompt 3 — Scan engine**
```
Implement scan_repository.dart: on Android use on_audio_query (MediaStore-based,
do NOT use raw filesystem folder walking — Android 11+ scoped storage blocks it).
On Windows use direct filesystem walk of user-selected folders. Read embedded metadata
via flutter_media_metadata. Support incremental rescan using date_modified comparison —
unchanged files must not be re-written to the DB. Mark files no longer found as
is_missing=1 rather than deleting them outright.
```

**Prompt 4 — Audio service**
```
Implement audio_player_service.dart wrapping just_audio + audio_service for background
playback, lock-screen/notification media controls, and queue management (add, reorder,
remove, play-next). No crossfade, no EQ, no ReplayGain — those are explicitly out of
scope for this phase.
```

**Prompt 5 — UI**
```
Build the four library tabs (Songs, Albums, Artists, Folders) as flat performant lists
using ListView.builder, a Now Playing screen, a Queue screen, basic Playlist
create/edit/delete screens, and a simple substring search screen. Follow Samsung
Music-style visual simplicity: large album art, minimal text density, max 2 navigation
layers deep. Use the theme defined in shared/theme — confirm color/typography choices
with me before finalizing if none exist yet.
```

---

## 6. WHAT'S DELIBERATELY DEFERRED (don't let Kiro "helpfully" add these early)

| Feature | Phase |
|---|---|
| MusicBrainz/Discogs/AcoustID metadata enrichment | 2 |
| Smart playlists, duplicate detection, library health | 2 |
| Fuzzy search, lyrics indexing | 2 |
| Full desktop tag editor, batch tools | 3 |
| Android ↔ Windows sync | 4 |
| Plugin system | 4 |
| Crossfade / ReplayGain / EQ / pitch control | 2–3 (revisit if just_audio can't support cleanly) |
| Handheld editions (PSP/Vita/3DS) | Future, separate lightweight rebuild — not a port |

If Kiro starts implementing anything from this table unprompted, point it back to this file.
