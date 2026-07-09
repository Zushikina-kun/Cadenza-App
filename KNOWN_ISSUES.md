# Cadenza — Known Issues & Fix Plan

**Last updated:** 2026-07-09
**Status:** Phase 1 scaffold complete. Build compiles and launches on Windows.
These are the confirmed gaps between what's running now and a usable Phase 1 MVP.

> **Research note (2026-07-09):** Two additional open-source players were cloned as reference:
> - **Namida** (`namidaco/namida`) — Flutter, Android + Windows, same stack (just_audio + audio_service + media_kit). Production quality. Direct reference for miniplayer architecture, scan isolate pattern, and reactive library state.
> - **SamsungMusicPort** (`AyraHikari/SamsungMusicPort`) — Decompiled Samsung Music APK. UI/UX reference only (res/layout XML). Used for miniplayer, now-playing, queue panel, and widescreen layout patterns.
>
> Several fix approaches below have been revised based on what was learned from Namida's codebase. See `PLAN.md` for the full revised build plan.

---

## 🔴 Critical — Blocks Basic Use

### 1. Scan hangs indefinitely on Windows

**Symptom:** User picks a folder with 1 FLAC file, taps "Scan Now", spinner runs forever.

**Root cause — three bugs:**

**Bug A — `flutter_media_metadata` blocks the UI isolate on Windows.**
`MetadataRetriever.fromFile()` is a channel call that goes to a native plugin. On Windows it appears to block or time out silently when the FLAC file path contains spaces or special characters, OR when the plugin DLL isn't loaded yet. Since `WindowsScanEngine` runs in the same async context as the UI, a blocking metadata call stalls the scan stream and it never emits `isComplete: true`.

**Revised fix (from Namida research):** Use a persistent background `Isolate` with a `ReceivePort` for all metadata work during a scan — not just `compute()`. `compute()` spawns a new isolate per call, which is expensive at scale (5k tracks = 5k isolate spawns). A single persistent isolate receives file paths and sends back metadata structs. Add a per-file 10s timeout via `Future.any()`:
```dart
final meta = await Future.any([
  _metadataIsolate.sendAndReceive(path),
  Future.delayed(const Duration(seconds: 10), () => const TrackMetadata()),
]);
```
Also add a global scan watchdog — if the scan stream hasn't completed in 60 seconds per file, force-complete with whatever was scanned.

**Bug B — `ScanNotifier.startScan()` has a logic error with the `error` field.**
Inside the `await for` loop:
```dart
if (progress.error != null) {
  state = ScanState.error(message: progress.error!);
  break;
}
```
This check runs **after** the `isComplete` check, but the final `ScanProgress` emitted for empty-folder cases has `error: 'no_folders'` AND `isComplete: true`. The `isComplete` branch triggers, sets state to `done`, but then the provider is never invalidated properly if an error was also set. The UI shows "Scan complete" but the library stays empty with no user feedback.

**Fix:** Restructure the check order and handle `isComplete + error` as a distinct case.

**Bug C — `_upsertArtist()` is a no-op.**
`WindowsScanEngine._upsertArtist()` has the body commented out — artists are never written to the `artists` table during a scan. This doesn't hang the scan but means the Artists tab always shows empty even after a successful scan.

**Fix:** Implement using the raw DB from `_trackRepo`'s provider, or add an `ArtistRepository` and inject it into the scan engine.

---

### 2. Scan result never appears in library after completion

**Symptom:** Even if scan completes, Songs/Albums/Artists tabs keep showing spinner or empty state.

**Root cause:** `ScanNotifier` calls `_ref.invalidate(tracksProvider)` etc. on completion, but `tracksProvider` / `albumsProvider` are `FutureProvider` — invalidating them from inside a `StateNotifier` using a provider-scoped ref is not guaranteed to propagate the invalidation to all watching widgets.

**Revised fix (from Namida research):** Replace `FutureProvider` with in-memory reactive state. Namida uses in-memory lists (`tracksInfoList = <T>[].obs`) that the `Indexer` fills directly during scan. Library pages watch these lists — no provider invalidation needed. The Riverpod equivalent is:
- Replace `tracksProvider`, `albumsProvider`, `artistsProvider` with `StateNotifierProvider<LibraryNotifier, LibraryState>` where `LibraryState` holds the current in-memory lists.
- `ScanEngine` calls `ref.read(libraryNotifierProvider.notifier).updateTracks(scannedTracks)` after each batch.
- Library tabs read from `ref.watch(libraryNotifierProvider)` and rebuild automatically.

This also eliminates the round-trip back to SQLite on every screen rebuild — tracks are in memory after the first load, queries only happen on cold launch.

---

## 🟡 High — Missing Core UX Features

### 3. No back navigation on any screen

**Symptom:** Tapping Settings, Search, Now Playing, Queue navigates forward but there's no way back. The system back button works on Windows (Alt+Left) but there's no in-app back button rendered.

**Root cause:** `go_router` is configured with `GoRoute` (push-style navigation) but `context.go()` replaces the stack — `Navigator.canPop()` returns false and no back button appears.

**Fix options (pick one):**
- Switch settings/search/etc to `context.push()` instead of `context.go()` so they push onto the stack → AppBar gets automatic back button
- Add a `ShellRoute` wrapping the library so sub-routes get proper stack management
- Quickest: add explicit `leading: BackButton()` to every non-root AppBar manually

---

### 4. No widescreen / desktop layout

**Symptom:** On a desktop window, the app looks like a stretched phone app. No sidebar, no desktop-appropriate navigation.

**Revised fix (from Namida + Samsung Music research):**

Do NOT add a simple `NavigationRail` — use the **widescreen panel model** instead:

- **Portrait / narrow (<700px):** standard tab bar at top, miniplayer slides up from bottom as a full-screen overlay
- **Landscape / wide (≥700px):** now-playing panel permanently docked to the **right side** (~40% width), library fills the left. Nav rail on the left for Songs/Albums/Artists/Folders/Playlists.

This is exactly what Namida does (`Dimensions.miniplayerIsWideScreen`) and what Samsung Music does with its `sw500dp`/`sw711dp` layout variants. It's more native to desktop than a miniplayer + nav rail combo.

Implementation: wrap `MainScreen` in a `LayoutBuilder`. When `width > 700`:
```dart
Row(children: [
  NavigationRail(...),          // left ~56px
  Expanded(child: LibraryView), // fills remaining left space
  SizedBox(width: playerWidth, child: NowPlayingPanel), // right panel, always visible
])
```

---

### 5. No proper miniplayer — needs full reimplementation

**Symptom:** The current miniplayer returns `SizedBox.shrink()` when nothing is playing and is a thin stub otherwise. No gesture-driven expand/collapse, no queue view.

**Revised fix (from Namida research):**

Replace the current stub entirely. The correct architecture (as used by Namida) is:

- Single `AnimationController` with `upperBound: 2.0`:
  - `value = 0.0` → mini bar at bottom
  - `value = 1.0` → full-screen now playing
  - `value = 2.0` → queue panel (swiped up from expanded)
- Gesture-driven: drag up to expand, drag up again to reveal queue, drag down to collapse
- Three snap positions: mini, expanded, queue
- In widescreen mode: always at `value = 1.0`, docked to right side, no mini state
- Show a static "Tap a song to play" placeholder bar so the affordance is always visible even before first playback

Reference: `namida/lib/controller/miniplayer_controller.dart` and `namida/lib/main_page_wrapper.dart`.

---

### 6. No way to access Playlists from the main screen

**Symptom:** The Playlists screen exists at `/playlists` but there's no button or tab to reach it.

**Fix:** Add Playlists as a 5th item in the NavigationRail (widescreen) or as a 5th tab (narrow).

---

### 7. Settings screen has no visual feedback after scan completes or errors

**Symptom:** The scan spinner disappears after completion with no success count, no timestamp, no error details.

**Fix:** Show `ScanProgress` details in the subtitle: "Scanned 47 tracks (12 new, 35 unchanged)" and a timestamp. Show specific error messages (e.g. "No audio files found" vs "Permission denied" vs "Folder not found").

---

### 8. No shuffle or repeat controls

**Symptom:** Now Playing has play/pause/skip but no shuffle or repeat button.

**Fix:** Add shuffle and repeat mode toggles via `just_audio`'s `setShuffleModeEnabled()` and `setLoopMode()`, then surface the buttons in `NowPlayingScreen`.

---

## 🟠 Medium — Functional Gaps

### 9. Artist writes are silently skipped during scan

As noted in Bug C above — `_upsertArtist()` in `WindowsScanEngine` is an empty method. Artists tab always shows empty after scan.

### 10. No "Add to playlist" flow from track context menu

**Symptom:** The `TrackListTile` has an "Add to playlist" menu item but tapping it does nothing — the handler is `null` in all current usage sites.

**Fix:** Implement a bottom sheet or dialog that lists existing playlists and lets the user pick one. Wire up `PlaylistRepository.addTrackToPlaylist()`.

### 11. Folders tab shows scan folders but not their tracks

**Symptom:** The Folders tab lists registered scan folders but tapping a folder does nothing.

**Fix:** Make each folder tile navigable to a filtered track list showing only tracks whose `file_path` starts with that folder's path.

### 12. Search results not grouped

**Requirement 14.4:** Results should be grouped by Tracks / Albums / Artists. Currently returns a flat list of tracks only.

**Fix:** Run three queries (by title, by album, by artist) and display in `SliverList` sections with headers.

### 13. Windows title bar is default Flutter chrome

The app window has no custom title bar or drag region. On Windows 11 the default Flutter chrome looks out of place for a media player.

**Fix (optional polish):** Add `window_manager` package and implement a custom title bar with min/max/close buttons and a drag region. Reference: `namida/lib/main_page_wrapper.dart` (`NamidaDesktopAppBar` and `WrapWithWindowGoodies`).

---

## 🟢 Low — Polish

### 14. No window size / position persistence on Windows

**Fix:** Use `window_manager` to save/restore window bounds via `SharedPreferences`.

### 15. App icon is the default Flutter blue cube

**Fix:** Replace `cadenza/windows/runner/resources/app_icon.ico` and Android launcher icons in `android/app/src/main/res/mipmap-*/` with a proper Cadenza icon.

### 16. No keyboard shortcuts on Windows

Expected for a desktop player: Space = play/pause, Left/Right arrows = seek ±5s, Ctrl+Left/Right = previous/next track.

**Fix:** Add `Focus` + `KeyboardListener` at the app level. Reference: Namida's `ShortcutsController` → `ShortcutsManager.platform()` pattern. For global media keys, `audio_service_win` already wires SMTC which handles media key interception at the OS level.

---

## Fix Priority Order

| # | Issue | Priority | Effort | Revised? |
|---|---|---|---|---|
| 1 | Scan hangs (metadata blocking + artist no-op) | 🔴 Critical | Medium | ✅ Use persistent isolate |
| 2 | Library doesn't refresh after scan | 🔴 Critical | Small | ✅ Replace FutureProvider with in-memory state |
| 3 | No back navigation | 🟡 High | Small | — |
| 4 | No widescreen desktop layout | 🟡 High | Medium | ✅ Widescreen panel model (not just nav rail) |
| 5 | Miniplayer needs full rewrite | 🟡 High | Large | ✅ AnimationController 3-state model |
| 6 | Playlists unreachable | 🟡 High | Small | — |
| 7 | No scan feedback | 🟡 High | Small | — |
| 8 | No shuffle/repeat | 🟠 Medium | Small | — |
| 9 | Artist writes skipped | 🟠 Medium | Small | — |
| 10 | Add to playlist no-op | 🟠 Medium | Medium | — |
| 11 | Folders tab doesn't navigate | 🟠 Medium | Small | — |
| 12 | Search not grouped | 🟠 Medium | Small | — |
| 13–16 | Polish items | 🟢 Low | Varies | — |

---

## Next Session Plan

Fix items 1–3 in a single pass (critical path: scan works → library populates → navigation works), then tackle 4+5 together (widescreen layout + real miniplayer), then 6–8.

See `PLAN.md` for the full phased build plan including Samsung Music UI patterns and Windows desktop polish.
