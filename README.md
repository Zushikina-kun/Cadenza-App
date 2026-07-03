# Cadenza

An offline-first local music player for **Android** and **Windows**, built with Flutter 3.x.

> Phase 1 MVP — all functionality is entirely local. No network, no cloud, no streaming.

---

## Stack

| Layer | Choice |
|---|---|
| Framework | Flutter 3.x (single codebase, Android + Windows) |
| State management | Riverpod 2.x |
| Local database | sqflite (Android) / sqflite_common_ffi (Windows) |
| Audio engine | just_audio + just_audio_media_kit (libmpv backend on Windows) |
| Background audio | audio_service (Android foreground service + lock screen) + audio_service_win (Windows SMTC) |
| Media scanning | on_audio_query / MediaStore (Android) · dart:io recursive walk (Windows) |
| Metadata | flutter_media_metadata (alexmercerind fork — all platforms) |
| Navigation | go_router |

---

## Project Structure

```
cadenza/
├── lib/
│   ├── main.dart                        # App entry, platform init, router
│   ├── core/
│   │   ├── database/
│   │   │   ├── db_provider.dart         # sqflite / sqflite_ffi bootstrap
│   │   │   └── schema.dart              # Full DDL (tracks, albums, artists, playlists…)
│   │   ├── models/                      # Track, Album, Artist, Playlist, ScanFolder
│   │   ├── repositories/               # TrackRepo, AlbumRepo, PlaylistRepo, ScanRepo
│   │   ├── services/
│   │   │   ├── scan/                    # ScanEngine interface + Windows/Android impls
│   │   │   ├── audio/                   # AudioPlayerService + Desktop/Android impls
│   │   │   ├── metadata_reader_service.dart
│   │   │   └── artwork_cache_service.dart
│   │   └── providers/
│   │       └── providers.dart           # All Riverpod providers
│   ├── features/
│   │   ├── library/                     # Songs / Albums / Artists / Folders tabs
│   │   ├── now_playing/                 # Full-screen now playing + seek bar
│   │   ├── queue/                       # Reorderable queue screen
│   │   ├── playlists/                   # Playlist list + detail (create/rename/delete)
│   │   ├── search/                      # Substring search (title / artist / album)
│   │   └── settings/                   # Folder management, theme toggle, scan trigger
│   └── shared/
│       ├── widgets/                     # TrackListTile, EmptyState
│       └── theme/                       # AppTheme (light + dark, Material 3)
├── android/                             # Android platform folder
├── windows/                             # Windows platform folder
└── pubspec.yaml
```

---

## Prerequisites

### Windows
- [Flutter SDK 3.x](https://docs.flutter.dev/get-started/install/windows)
- **Visual Studio** with the **"Desktop development with C++"** workload — required for Windows builds
- **Windows Developer Mode** enabled (`Settings → Privacy & Security → Developer Mode`)

### Android
- Android SDK (via Android Studio or command-line tools)
- A device or emulator running Android 5.0+ (API 21+)

---

## Getting Started

```bash
# 1. Clone
git clone https://github.com/Zushikina-kun/Cadenza-App.git
cd Cadenza-App/cadenza

# 2. Install dependencies
flutter pub get

# 3a. Run on Windows
flutter run -d windows

# 3b. Run on Android (device connected or emulator running)
flutter run -d android
```

---

## Phase 1 Feature Scope

### In scope (built)
- Folder/library scan → SQLite track index
- Embedded metadata reading (title, artist, album, artwork, etc.)
- Library views: **Songs / Albums / Artists / Folders** (4 tabs)
- Now Playing screen (artwork, controls, seek bar)
- Queue (add, reorder, remove, play next)
- Basic playlists (create, rename, delete, reorder tracks)
- Substring search (title / artist / album)
- Background playback + media notification controls (Android)
- Incremental rescan (unchanged files write zero rows)
- Settings screen (add/remove folders, theme toggle, scan now)
- Light / Dark theme, persisted across restarts

### Explicitly out of Phase 1
See `CADENZA_PHASE1_SPEC.md` section 7 for the full deferred list (MusicBrainz, smart playlists, crossfade, EQ, sync, plugins, etc.).

---

## Build Status

| Check | Status |
|---|---|
| `flutter analyze` | ✅ 0 issues |
| Windows build | Requires Developer Mode enabled |
| Android build | Requires Android SDK |

---

## Spec

Full Phase 1 build spec: [`CADENZA_PHASE1_SPEC.md`](./CADENZA_PHASE1_SPEC.md)

Kiro spec (requirements / design / tasks): [`.kiro/specs/cadenza-phase1-mvp/`](./.kiro/specs/cadenza-phase1-mvp/)
