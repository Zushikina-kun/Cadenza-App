# CADENZA — PHASE 1 BUILD SPEC (MVP)
**Scope:** Android + Windows, offline-first local music player.
**Not in this doc:** Sync, plugins, streaming connectors, handheld editions, AI tools — all Phase 3/4, deliberately excluded so Kiro doesn't scope-creep the MVP.

---

> **Revision note — 2026-07-09:**
> Two reference repos were cloned and analyzed. Several implementation approaches in this spec have been superseded. See `PLAN.md` for the full revised build plan and `KNOWN_ISSUES.md` for updated fix strategies. Summary of key changes:
>
> - **Scan engine:** Use a persistent background `Isolate` (not `compute()`) for metadata reads — avoids repeated isolate spawn overhead at scale. See `PLAN.md` Phase A1.
> - **Library state:** Replace `FutureProvider` + `invalidate()` with in-memory reactive `StateNotifierProvider`. Scan engine updates the list directly; no invalidation needed. See `PLAN.md` Phase A2.
> - **Miniplayer:** Replace the current stub with a full 3-state `AnimationController` (mini / expanded / queue). See `PLAN.md` Phase B2+B3.
> - **Desktop layout:** Use the widescreen docked-panel model (player on right, library on left) instead of a nav rail + bottom miniplayer. Breakpoint: 700px wide. See `PLAN.md` Phase B2.
> - **Reference implementations:** `namidaco/namida` (Flutter, same stack, production quality) and `AyraHikari/SamsungMusicPort` (Samsung Music decompiled APK, UI/UX reference).

---

## 0. STACK DECISION (LOCKED)

| Layer | Choice | Why |
|---|---|---|
| Framework | **Flutter 3.x** | Single codebase for Android + Windows desktop; you already know this stack from SmartSpend |
| Local DB | **sqflite** (Android) — see note below for Windows | Matches SmartSpend, zero new learning curve |
| Audio engine | **just_audio** on Android, **just_audio + just_audio_media_kit** (libmpv backend) on Windows | Revised — see "AUDIO ENGINE FIX" below, this was a real gap in the first pass |
| Background playback / media controls | **audio_service** (Android/iOS/Linux) + **audio_service_win** (Windows SMTC) | First pass didn't account for Windows — audio_service has no native Windows support without this add-on package |
| File scanning | **MediaStore** via `on_audio_query` plugin (Android) / direct filesystem walk (Windows) | Avoids raw folder scanning on Android 11+ scoped storage — this is mandatory, not optional |
| Metadata read (local tags) | **flutter_media_metadata** (alexmercerind fork — supports Windows, Linux, macOS, Android, iOS, Web) | One package, all target platforms — don't use a metadata reader that's mobile-only |
| State management | **Riverpod** | Locked decision — Cadenza's long-range state surface (playback, queue, scan progress, multi-screen sync, eventual plugin system per VISION.md) benefits from Riverpod's compile-time safety more than a smaller app like SmartSpend does; worth eating the learning curve now while the codebase is small |

**Windows DB note:** `sqflite` doesn't support Windows natively. Use `sqflite_common_ffi` for desktop, same SQL schema, different bootstrap. Tell Kiro this explicitly or it'll try to run mobile sqflite on Windows and fail silently on first launch.

**Online metadata (MusicBrainz/Discogs/Last.fm/AcoustID) is OUT of Phase 1 entirely.** Local tag reading only. This directly resolves the offline-first contradiction flagged earlier — nothing in MVP requires network.

### ⚠️ Audio engine fix (this corrects what I gave you last time)

- Plain `just_audio` on Windows runs over `just_audio_windows`, implemented on the **WinRT MediaPlayer** API. It works, but WinRT's format support is narrower than what Cadenza's original spec promises — FLAC/OGG/OPUS/ALAC aren't guaranteed to play cleanly across every encoder.
- The fix real Flutter music-player projects use is **`just_audio_media_kit`** — a drop-in backend that routes `just_audio` through **libmpv** on Windows and Linux instead of WinRT. libmpv has the best real-world format compatibility of anything available to Flutter, which matters given your format list.
- You still write against the same `just_audio` API — this is a backend swap, not an architecture change. Android stays on plain `just_audio`, already solid there.
- **Windows media controls**: `audio_service` has no built-in Windows implementation (only Android/iOS/web/Linux-via-mpris). You need the companion package **`audio_service_win`**, which adds Windows System Media Transport Controls (SMTC) support — this is what makes media keys, the taskbar thumbnail controls, and the Windows 11 "now playing" flyout work. Skip it and Windows playback works but has zero OS-level media integration.

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
  composer TEXT,             -- nullable, unused in Phase 1 UI, cheap to capture now
  conductor TEXT,            -- nullable, unused in Phase 1 UI, cheap to capture now
  genre TEXT,
  label TEXT,                -- record label, nullable, unused in Phase 1 UI
  year INTEGER,
  track_number INTEGER,
  disc_number INTEGER,
  duration_ms INTEGER,
  file_size INTEGER,
  cue_sheet_path TEXT,       -- nullable; if set, track is a CUE-sheet virtual split — Phase 2 feature, field just reserved now
  rating INTEGER DEFAULT 0,      -- 0-5, unused in Phase 1 UI
  is_favorite INTEGER DEFAULT 0, -- unused in Phase 1 UI
  play_count INTEGER DEFAULT 0,  -- unused in Phase 1 UI
  last_played INTEGER,           -- unix timestamp, unused in Phase 1 UI
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
  label TEXT,                -- unused in Phase 1 UI, reserved
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
- **`composer`, `conductor`, `label`, `cue_sheet_path`, `rating`, `is_favorite`, `play_count`, `last_played` are schema-reserved but Phase 1 UI must NOT expose them.** They exist now purely to avoid a painful migration later — don't build any screen, filter, or sort around them yet. If a Phase 1 UI screen references any of these, that's scope creep, stop and flag it.

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
Android applicationId: com.lucidframe.cadenza (confirm/adjust if you have a different
package naming convention). Windows app identity name: Cadenza.
Add dependencies: sqflite, sqflite_common_ffi, path_provider, just_audio,
just_audio_media_kit, media_kit_libs_windows_audio, audio_service, audio_service_win,
on_audio_query, flutter_media_metadata (use the alexmercerind fork, which supports
Windows/Linux/macOS/Android/iOS/Web — not the original mobile-only package),
flutter_riverpod. On Android, target minSdkVersion appropriate for READ_MEDIA_AUDIO
(Android 13+ granular media permission) with a fallback to READ_EXTERNAL_STORAGE for
older versions — use permission_handler for this.
Create the folder structure exactly as specified in CADENZA_PHASE1_SPEC.md section 3.
Do not add any packages related to networking, MusicBrainz, or cloud sync — this is an
offline-only Phase 1 build.
```
*(Windows build prerequisite, already satisfied: Visual Studio with the "Desktop development with C++" workload must be installed before `flutter run -d windows` will work.)*

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
Implement audio_player_service.dart wrapping just_audio for playback. On Windows,
initialize just_audio_media_kit (JustAudioMediaKit.ensureInitialized()) so playback
routes through libmpv instead of WinRT MediaPlayer — this is required for reliable
FLAC/OGG/OPUS/ALAC support. Wire up audio_service for background playback and media
controls on Android; audio_service_win handles the Windows SMTC integration
automatically once added as a dependency, no separate Windows-specific handler code
should be needed beyond the standard AudioHandler implementation. Implement queue
management (add, reorder, remove, play-next). No crossfade, no EQ, no ReplayGain —
those are explicitly out of scope for this phase.
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

## 6. OPTIONAL WINDOWS DESKTOP POLISH (nice-to-have, not blocking)

Not required for Phase 1 done-ness, but cheap to add if Kiro has slack — these match your original "Windows 11 Media Player" visual inspiration and are commonly paired with `media_kit`-based players:
- **`windows_taskbar`** — adds play/pause/skip buttons and progress to the Windows taskbar thumbnail preview, a small but very "native app" touch for a music player specifically
- **`window_manager`** — custom title bar / window chrome control if you want something less default-Win32 than the stock Flutter window
- **`fluent_ui`** — optional if you want actual Windows 11 Fluent Design widgets instead of Material on desktop; skip this if it adds too much design-system overhead for Phase 1 — Material everywhere is a perfectly fine MVP choice and keeps Android/Windows visually consistent

Don't let Kiro pull these in until the core scan/playback/library loop in section 1 is done and tested — polish before correctness is how Phase 1 timelines slip.

---

## 7. WHAT'S DELIBERATELY DEFERRED (don't let Kiro "helpfully" add these early)

| Feature | Phase |
|---|---|
| MusicBrainz/Discogs/AcoustID metadata enrichment | 2 |
| Smart playlists, duplicate detection, library health dashboard | 2 |
| Fuzzy search, lyrics indexing | 2 |
| Ratings, favorites, play count/last-played surfaced in UI | 2 |
| CUE sheet parsing/virtual track splitting | 2 |
| Full desktop tag editor, batch tools (batch rename, batch tag edit) | 3 |
| Artwork downloader, CD ripping, format conversion | 3 |
| Composer/conductor/label fields surfaced in library views | 3 |
| Theme system (One UI / Fluent / Material You / AMOLED / custom accents) | 3 |
| Android ↔ Windows sync — protocol still undefined, needs its own design pass before any Phase 3 work starts | 3 |
| Plugin system | 4 |
| Crossfade / ReplayGain / EQ / parametric EQ / tempo / pitch control | 2–3 (media_kit's libmpv backend can likely support most of this later without a backend swap — good argument for the Phase 1 audio engine choice holding up long-term) |
| Android Auto, Wear OS, widgets, Material You dynamic color | 3–4 |
| Local-only AI features (playlist generation, underplayed-song surfacing, duplicate/metadata suggestions) | 4 — stays offline-first since it runs against your own library, no new network dependency |
| NAS / Jellyfin / Navidrome integration, web companion | 4+ |
| DSD support | Unscheduled — narrow audience, revisit only if there's real demand |
| Handheld editions (PSP/Vita/3DS) | Future, separate lightweight rebuild — not a port |

If Kiro starts implementing anything from this table unprompted, point it back to this file.