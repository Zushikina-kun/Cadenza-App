# Cadenza — Known Issues & Fix Plan

**Last updated:** 2026-07-03  
**Status:** Phase 1 scaffold complete. Build compiles and launches on Windows.  
These are the confirmed gaps between what's running now and a usable Phase 1 MVP.

---

## 🔴 Critical — Blocks Basic Use

### 1. Scan hangs indefinitely on Windows

**Symptom:** User picks a folder with 1 FLAC file, taps "Scan Now", spinner runs forever.

**Root cause — two bugs:**

**Bug A — `flutter_media_metadata` blocks the UI isolate on Windows.**  
`MetadataRetriever.fromFile()` is a channel call that goes to a native plugin. On Windows it appears to block or time out silently when the FLAC file path contains spaces or special characters, OR when the plugin DLL isn't loaded yet. Since `WindowsScanEngine` runs in the same async context as the UI, a blocking metadata call stalls the scan stream and it never emits `isComplete: true`.

**Fix:** Wrap each `readMetadata` call in `compute()` to push it off the main isolate, with an explicit timeout:
```dart
final meta = await Future.any([
  compute(_readMetadataIsolate, path),
  Future.delayed(const Duration(seconds: 10), () => const TrackMetadata()),
]);
```
Also add a global scan timeout — if the scan stream hasn't completed in 60 seconds per file, force-complete with whatever was scanned.

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

**Fix:** Implement it using the raw DB from `_trackRepo`'s provider, or add an `ArtistRepository` and inject it into the scan engine.

---

### 2. Scan result never appears in library after completion

**Symptom:** Even if scan completes, Songs/Albums/Artists tabs keep showing spinner or empty state.

**Root cause:** `ScanNotifier` calls `_ref.invalidate(tracksProvider)` etc. on completion, but `tracksProvider` / `albumsProvider` are `FutureProvider` — invalidating them triggers a rebuild, but the tabs use `ref.watch()` which should pick up the new value. The bug is that `ScanNotifier` is created with `ref.read(scanEngineProvider)` inside `StateNotifierProvider`, and the `Ref` passed in is a `Ref<ScanState>` — calling `_ref.invalidate(tracksProvider)` from inside a `StateNotifier` using a provider-scoped ref is not guaranteed to propagate the invalidation to all widgets watching those providers.

**Fix:** Use a proper `invalidate` approach — either pass a `WidgetRef` callback into the notifier, or switch `tracksProvider` / `albumsProvider` to `StreamProvider` backed by the DB, so they auto-update when the DB changes.

---

## 🟡 High — Missing Core UX Features

### 3. No back navigation on any screen

**Symptom:** Tapping Settings, Search, Now Playing, Queue navigates forward but there's no way back. The system back button works on Windows (Alt+Left) but there's no in-app back button rendered.

**Root cause:** `go_router` is configured with `GoRoute` (push-style navigation) but the AppBar doesn't automatically get a back button unless the route is pushed onto a shell route stack. Since we're using `context.go()` (replace, not push), there's no navigation stack — `Navigator.canPop()` returns false and no back button appears.

**Fix options (pick one):**
- Switch settings/search/etc to `context.push()` instead of `context.go()` so they push onto the stack → AppBar gets automatic back button
- Or add a `ShellRoute` wrapping the library so sub-routes get proper stack management
- For now: add explicit `leading: BackButton()` or `leading: IconButton(Icons.arrow_back)` to every non-root AppBar manually

---

### 4. No sidebar / navigation rail for Windows desktop

**Symptom:** On a desktop window, the tab bar at the top is functional but there's no sidebar navigation rail — standard for Windows desktop music players. The app looks like a stretched phone app.

**Root cause:** The current `LibraryScreen` uses `TabBar` + `TabBarView` only — no responsive layout switching to `NavigationRail` on wider screens.

**Fix:** Wrap the library body in a `LayoutBuilder`. When width > 600px, show a `NavigationRail` on the left with Songs/Albums/Artists/Folders + Playlists items. When narrow (phone), keep the tab bar. This is the standard Flutter adaptive pattern.

---

### 5. No way to access Playlists from the main screen

**Symptom:** The Playlists screen exists at `/playlists` but there's no button or tab to reach it from the library. It's unreachable unless you type the URL.

**Fix:** Add Playlists as a 5th tab in the library, or include it in the sidebar/navigation rail (preferred for desktop).

---

### 6. Mini-player is invisible until a track is playing

**Symptom:** The bottom mini-player is entirely hidden (returns `SizedBox.shrink()`) when nothing is playing, so new users have no indication that tapping a song will play it or that a player exists.

**Fix:** Show a static "Not playing" placeholder bar that says "Tap a song to play" so the player affordance is always visible. Only animate/show artwork/controls once something is playing.

---

### 7. Settings screen has no visual feedback after scan completes or errors

**Symptom:** The scan spinner disappears after completion but there's no success count ("Scanned 47 tracks"), no timestamp, and no error details if something goes wrong — just "Scan complete" or nothing.

**Fix:** Show `ScanProgress` details in the subtitle: "Scanned 47 tracks (12 new, 35 unchanged)" and timestamp. Show specific error messages (e.g. "No audio files found" vs "Permission denied" vs "Folder not found").

---

### 8. No shuffle or repeat controls

**Symptom:** Now Playing has play/pause/skip but no shuffle or repeat button — expected by users in any music player.

**Fix:** Add shuffle and repeat mode toggles to `DesktopAudioPlayerService` via `just_audio`'s `setShuffleModeEnabled()` and `setLoopMode()`, then surface the buttons in `NowPlayingScreen`.

---

## 🟠 Medium — Functional Gaps

### 9. Artist writes are silently skipped during scan

As noted in Bug C above — `_upsertArtist()` in `WindowsScanEngine` is an empty method. No artists are ever written to the `artists` table, so the Artists tab always shows empty even after a successful scan.

### 10. No "Add to playlist" flow from track context menu

**Symptom:** The `TrackListTile` has an "Add to playlist" menu item but tapping it does nothing — the handler is `null` in all current usage sites.

**Fix:** Implement a bottom sheet or dialog that lists existing playlists and lets the user pick one. Wire up `PlaylistRepository.addTrackToPlaylist()`.

### 11. Folders tab shows scan folders but not their tracks

**Symptom:** The Folders tab lists registered scan folders but doesn't show the tracks inside them. Tapping a folder does nothing.

**Fix:** Make each folder tile navigable to a filtered track list showing only tracks whose `file_path` starts with that folder's path.

### 12. Search results not grouped

**Requirement 14.4:** Results should be grouped by Tracks / Albums / Artists. Currently it returns a flat list of tracks only — album and artist matches aren't separated.

**Fix:** Run three queries (by title, by album, by artist) and display in `SliverList` sections with headers.

### 13. Windows title bar is default Flutter chrome

The app window has no custom title bar or drag region. On Windows 11 the default flutter chrome looks out of place for a media player.

**Fix (optional polish):** Add `window_manager` package and implement a custom title bar with min/max/close buttons and a drag region. This is the "nice-to-have" item from the spec section 6.

---

## 🟢 Low — Polish

### 14. No window size / position persistence on Windows

The window opens at a default Flutter size every launch. Users expect media players to remember their window size and position.

**Fix:** Use `window_manager` to save/restore window bounds via `SharedPreferences`.

### 15. App icon is the default Flutter blue cube

**Fix:** Replace `cadenza/windows/runner/resources/app_icon.ico` and Android launcher icons in `android/app/src/main/res/mipmap-*/` with a proper Cadenza icon.

### 16. No keyboard shortcuts on Windows

Expected for a desktop player: Space = play/pause, Left/Right arrows = seek ±5s, Ctrl+Left/Right = previous/next track.

**Fix:** Add `Focus` + `KeyboardListener` or use `Shortcuts` + `Actions` in the library/now-playing screens.

---

## Fix Priority Order

| # | Issue | Priority | Effort |
|---|---|---|---|
| 1 | Scan hangs (metadata blocking + artist no-op) | 🔴 Critical | Medium |
| 2 | Library doesn't refresh after scan | 🔴 Critical | Small |
| 3 | No back navigation | 🟡 High | Small |
| 4 | No sidebar / nav rail for desktop | 🟡 High | Medium |
| 5 | Playlists unreachable | 🟡 High | Small |
| 6 | Mini-player always hidden | 🟡 High | Small |
| 7 | No scan feedback | 🟡 High | Small |
| 8 | No shuffle/repeat | 🟠 Medium | Small |
| 9 | Artist writes skipped | 🟠 Medium | Small |
| 10 | Add to playlist no-op | 🟠 Medium | Medium |
| 11 | Folders tab doesn't navigate | 🟠 Medium | Small |
| 12 | Search not grouped | 🟠 Medium | Small |
| 13–16 | Polish items | 🟢 Low | Varies |

---

## Next Session Plan

Fix items 1–7 in a single pass (all critical/high, small–medium effort) then retest with the 1-FLAC folder to confirm the scan loop works end-to-end.
