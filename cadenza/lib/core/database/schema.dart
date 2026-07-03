/// DDL statements executed in order on first database open.
/// All statements use IF NOT EXISTS so re-entrant opens are safe.
const List<String> kSchemaStatements = [
  // ── Tables ──────────────────────────────────────────────────────────────
  '''
  CREATE TABLE IF NOT EXISTS tracks (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    file_path TEXT NOT NULL UNIQUE,
    title TEXT,
    artist TEXT,
    album TEXT,
    album_artist TEXT,
    composer TEXT,
    conductor TEXT,
    genre TEXT,
    label TEXT,
    year INTEGER,
    track_number INTEGER,
    disc_number INTEGER,
    duration_ms INTEGER,
    file_size INTEGER,
    cue_sheet_path TEXT,
    rating INTEGER DEFAULT 0,
    is_favorite INTEGER DEFAULT 0,
    play_count INTEGER DEFAULT 0,
    last_played INTEGER,
    date_added INTEGER,
    date_modified INTEGER,
    artwork_path TEXT,
    is_missing INTEGER DEFAULT 0
  )
  ''',
  '''
  CREATE TABLE IF NOT EXISTS albums (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    album_artist TEXT,
    year INTEGER,
    label TEXT,
    artwork_path TEXT,
    UNIQUE(name, album_artist)
  )
  ''',
  '''
  CREATE TABLE IF NOT EXISTS artists (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL UNIQUE
  )
  ''',
  '''
  CREATE TABLE IF NOT EXISTS playlists (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    date_created INTEGER,
    date_modified INTEGER
  )
  ''',
  '''
  CREATE TABLE IF NOT EXISTS playlist_tracks (
    playlist_id INTEGER NOT NULL,
    track_id INTEGER NOT NULL,
    position INTEGER NOT NULL,
    FOREIGN KEY (playlist_id) REFERENCES playlists(id) ON DELETE CASCADE,
    FOREIGN KEY (track_id) REFERENCES tracks(id) ON DELETE CASCADE
  )
  ''',
  '''
  CREATE TABLE IF NOT EXISTS scan_folders (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    folder_path TEXT NOT NULL UNIQUE,
    last_scanned INTEGER
  )
  ''',

  // ── Indexes ──────────────────────────────────────────────────────────────
  'CREATE INDEX IF NOT EXISTS idx_tracks_album ON tracks(album)',
  'CREATE INDEX IF NOT EXISTS idx_tracks_artist ON tracks(artist)',
  'CREATE INDEX IF NOT EXISTS idx_tracks_title ON tracks(title)',
];
