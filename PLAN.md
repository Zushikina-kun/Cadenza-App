# Cadenza — Full Build Plan

**Last updated:** 2026-07-09
**Current state:** Phase 1 scaffold complete. App compiles and launches on Windows. Critical scan and library-refresh bugs block end-to-end use.

---

## Reference Repos

Three repos were cloned alongside Cadenza to inform the build plan:

| Repo | URL | Purpose |
|---|---|---|
| SamsungMusicPort | `AyraHikari/SamsungMusicPort` | UI/UX reference. Decompiled Samsung Music APK. `res/layout/` XML files show exact layout structures for miniplayer, full player, queue panel, lock screen controls, and responsive widescreen variants. |
| Namida | `namidaco/namida` | Code reference. Flutter, Android + Windows, same stack (just_audio + audio_service + media_kit + on_audio_query). Production-quality implementations of: persistent scan isolate, reactive in-memory library state, 3-state AnimationController miniplayer, widescreen docked panel layout, custom Windows title bar, SMTC integration, keyboard shortcuts. |
| Spotube | `KRTirtho/spotube` | Partial clone only (incomplete). Flutter + Riverpod + Drift. Lower priority reference. |

Key insights from Namida's codebase that changed the plan:
1. **Persistent isolate for scan**, not `compute()` — avoids 5k isolate spawns for a 5k-track library
2. **In-memory reactive state** for the library, not `FutureProvider` invalidation — instant UI updates after scan
3. **Widescreen = player docks to the right**, not a nav rail + bottom miniplayer
4. **Miniplayer is a 3-state `AnimationController`** (mini/expanded/queue), not separate screens
5. **`window_manager` + `windows_taskbar`** integration patterns visible in `NamidaDesktopAppBar`

---

## Phase A — Fix the Critical Path

Nothing else is worth building until the scan → library → playback loop works end-to-end.

### A1. Fix Windows scan engine

**Files:** `lib/core/services/scan/windows_scan_engine.dart`, `lib/core/providers/providers.dart`

- Replace per-call `compute()` with a **persistent background `Isolate`** (spawn once, communicate via `ReceivePort`/`SendPort`)
- Per-file 10s timeout via `Future.any([isolate.sendAndReceive(path), Future.delayed(10s, () => TrackMetadata())])`
- Global scan watchdog: if total scan exceeds 60s × number of files, force-complete with partial results
- Fix `ScanNotifier` error/isComplete ordering bug — handle `isComplete: true` + `error != null` as a distinct "completed with warnings" state, not a silent success
- Reference: `namida/lib/controller/indexer_controller.dart` (`_fetchAllSongsAndWriteToFile`)

### A2. Fix library refresh after scan

**Files:** `lib/core/providers/providers.dart`, `lib/features/library/*.dart`

- Replace `tracksProvider`, `albumsProvider`, `artistsProvider` `FutureProvider`s with a single `StateNotifierProvider<LibraryNotifier, LibraryState>`
- `LibraryState` holds: `List<Track> tracks`, `List<Album> albums`, `List<Artist> artists` in memory
- On cold launch: `LibraryNotifier` loads from SQLite once, fills the lists
- During scan: `ScanEngine` calls `libraryNotifier.updateTracks(batch)` after each batch write — UI updates immediately
- Library tabs watch `ref.watch(libraryNotifierProvider)` — rebuilds reactively, no invalidation
- Reference: Namida's `Indexer.tracksInfoList` + `mainMapAlbums` / `mainMapArtists` in-memory maps

### A3. Implement `_upsertArtist()`

**File:** `lib/core/services/scan/windows_scan_engine.dart`

- The method body is commented out — artists are never written to the `artists` table
- Implement using `ArtistRepository` (inject into scan engine) or raw DB reference

---

## Phase B — Navigation and Layout

### B1. Fix navigation stack

**File:** `lib/main.dart`

- Change all `context.go('/settings')`, `context.go('/search')`, etc. to `context.push()`
- Screens pushed with `.push()` automatically get a back button in their AppBar via `Navigator.canPop()`
- Keep `context.go('/')` only for the library root

### B2+B3. Widescreen layout + real miniplayer (do together)

**Files:** `lib/features/library/library_screen.dart`, `lib/features/now_playing/now_playing_screen.dart`, new `lib/shared/widgets/mini_player.dart`

**Layout model (from Namida + Samsung Music):**

```
Portrait / narrow (<700px wide):
┌────────────────────────────┐
│  AppBar + SearchBar        │
├────────────────────────────┤
│  [Songs][Albums][Artists]  │  ← TabBar
│  [Folders][Playlists]      │
├────────────────────────────┤
│  Library list content      │
│                            │
│                            │
├────────────────────────────┤
│  Mini player bar  ▶ ⏭     │  ← always visible, slides up
└────────────────────────────┘

Landscape / wide (≥700px wide):
┌──────┬─────────────────────┬──────────────────┐
│ Rail │  Library content    │  Now Playing     │
│  🎵  │                     │  (always visible │
│  💿  │  Songs list         │   docked right)  │
│  👤  │                     │                  │
│  📁  │                     │  art + controls  │
│  📋  │                     │  + seek bar      │
└──────┴─────────────────────┴──────────────────┘
```

**Miniplayer AnimationController:**
```dart
// value = 0.0 → mini bar
// value = 1.0 → full screen now playing
// value = 2.0 → queue visible (swiped up from expanded)
animation = AnimationController(
  vsync: this,
  upperBound: 2.03,
  lowerBound: -0.2,
  value: 0.0,
);
```
- Gesture detector wraps the entire screen stack
- Drag up → animate toward 1.0 (expand)
- Drag up again (when at 1.0) → animate toward 2.0 (queue)
- Drag down → animate toward 0.0 (collapse to mini)
- In widescreen: lock at 1.0, no drag gestures, full player always visible on right
- Static "Tap a song to play" placeholder when `currentTrack == null`
- Reference: `namida/lib/controller/miniplayer_controller.dart`

### B4. Shuffle + repeat controls

**File:** `lib/features/now_playing/now_playing_screen.dart`

- Wire `just_audio` `setShuffleModeEnabled()` and `setLoopMode()` into `DesktopAudioPlayerService`
- Add shuffle + repeat toggle buttons to `NowPlayingScreen` control row

### B5. Scan feedback

**File:** `lib/features/settings/settings_screen.dart`

- After scan completes, show: "Scanned 47 tracks (12 new, 35 unchanged, 2 errors)"
- Show last-scanned timestamp per folder
- Show specific error messages rather than generic failure text

---

## Phase C — Samsung Music UI Styling

Reference files from `SamsungMusicPort/res/layout/`:

| Layout file | Flutter widget | Notes |
|---|---|---|
| `mini_player_main.xml` | `MiniPlayerBar` | Artwork (48×48 rounded), title + artist (marquee if long), play/pause + skip right, thin progress line at bottom edge of bar |
| `full_player.xml` | `NowPlayingScreen` | Large square artwork (fills width), title + artist centered below, seek bar, 5-button row (prev, rew, play/pause, fwd, next) |
| `full_player_queue.xml` | `QueuePanel` | Slide-up panel layered over the expanded player, reorderable list, currently playing item highlighted |
| `full_player_seekbar_common.xml` | Seek bar widget | Scrubbing popup shows timestamp above thumb while dragging |
| `full_player_control_buttons_common.xml` | Control row | 5 buttons, outer two (prev/next) slightly smaller than center three |
| `full_player_shuffle.xml` + `full_player_repeat.xml` | Shuffle/repeat icons | Active state uses accent color tint |
| `lock_player.xml` | (Android only) | Already handled by `audio_service` notification |
| Widescreen variants (`sw500dp`, `sw711dp`) | Widescreen layout | Confirms right-side panel approach, album art becomes smaller thumbnail in wide mode |

Visual language to carry over to Flutter:
- Large album art, minimal text density, max 2 layers of navigation deep
- Accent color inherited from album art (palette extraction — Phase 2, skip for now)
- Bottom sheet for context menus rather than dropdown menus
- Consistent 8dp/16dp spacing grid

---

## Phase D — Windows Desktop Polish

Add after Phase B+C are solid. Do NOT pull these in before the scan/playback loop works.

| Feature | Package | Reference |
|---|---|---|
| Custom title bar (drag region, min/max/close) | `window_manager` | `namida/lib/main_page_wrapper.dart` → `NamidaDesktopAppBar` |
| Taskbar thumbnail controls (play/pause/skip) | `windows_taskbar` | `namida/pubspec.yaml` — already listed there |
| Window size/position persistence | `window_manager` + `SharedPreferences` | `namida/lib/controller/window_controller.dart` |
| Keyboard shortcuts | `Focus` + `KeyboardListener` | Space=play/pause, ←/→=seek ±5s, Ctrl+←/→=prev/next |
| App icon | Replace `.ico` + Android mipmaps | — |

**Note on SMTC (Windows System Media Transport Controls):**
Cadenza uses `audio_service_win` which adds basic SMTC support automatically. Namida uses a lower-level `smtc_windows` package for finer control. `audio_service_win` is sufficient for Phase 1 — the taskbar "Now Playing" flyout and media keys will work. Revisit in Phase D if more control is needed.

---

## Deferred Features (do not implement early)

| Feature | Phase |
|---|---|
| MusicBrainz / Discogs / AcoustID metadata enrichment | 2 |
| Album art palette extraction (accent color from art) | 2 |
| Smart playlists, duplicate detection | 2 |
| Fuzzy search, lyrics display (.lrc sync) | 2 |
| Ratings, favorites, play count surfaced in UI | 2 |
| CUE sheet parsing | 2 |
| Full tag editor, batch tools | 3 |
| Crossfade / ReplayGain / EQ | 2–3 |
| Composer/conductor/label in library views | 3 |
| Android ↔ Windows sync | 3 |
| Plugin system | 4 |
| Android Auto, Wear OS, widgets | 3–4 |
| Local AI features (playlist generation, etc.) | 4 |
| NAS / Jellyfin / Navidrome integration | 4+ |

---

## Execution Order

```
A1 (persistent scan isolate + timeout + error fix)
  → A2 (reactive in-memory library state)
    → A3 (artist upsert fix)
      → B1 (navigation stack: go → push)
        → B2+B3 (widescreen layout + AnimationController miniplayer)
          → B4 (shuffle/repeat)
            → B5 (scan feedback)
              → C (Samsung Music UI styling)
                → D (Windows desktop polish)
```

---

## Definition of Done — Phase 1 MVP

Ship-ready when all of the following hold (unchanged from `CADENZA_PHASE1_SPEC.md`):

- Scanning 5,000 local tracks completes in under 30 seconds on a Ryzen 5 5600
- Cold app launch to visible library list is under 2 seconds with a pre-scanned DB
- Rescanning an already-scanned library with zero file changes touches zero rows
- Playback survives app backgrounding and screen lock on Android with working notification controls
- No audible gap or crash between consecutive tracks in a 20-track queue
- Library survives force-close/reopen without re-scanning or losing playlists
- Windows build launches and scans a local folder without needing Android-specific code paths
- Miniplayer is always visible (with placeholder when nothing is playing)
- Playlists are reachable from the main navigation
- Back navigation works on all non-root screens
