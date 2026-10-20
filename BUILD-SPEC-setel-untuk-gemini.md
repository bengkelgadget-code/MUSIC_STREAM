# BUILD SPEC — "Setel" (Aplikasi Streaming Musik Pribadi)

**Pasangan dari:** `PRD-musik-pribadi.md` (baca itu dulu)
**Untuk:** AI coding agent (Gemini di Antigravity) — eksekutor pembangunan
**Auditor:** Muse — verifikasi hasil per fase
**Versi:** 1.0 — 20 Okt 2026

---

## §0 — Instruksi Kerja untuk Gemini (baca pertama)

1. Baca `PRD-musik-pribadi.md` sampai paham, lalu dokumen ini.
2. Kerjakan **per fase** (§7): Fase 0 → 1 → 2 → 3 → 4. Jangan loncat fase.
3. Setiap fase selesai: jalankan `flutter analyze`, pastikan **0 error & 0 warning**. Laporkan ringkasan: file dibuat/diubah + hasil analyze.
4. **Jangan ubah kontrak interface di §4** tanpa konfirmasi user. Itu perjanjian dengan auditor.
5. **Aturan emas (wajib, tidak bisa ditawar):** tidak pernah menyimpan stream URL YouTube ke database. Yang disimpan hanya `videoId` (+ metadata). Stream URL di-resolve ulang setiap kali lagu diputar.
6. Jangan tambah dependency di luar §2 tanpa alasan kuat dan izin user.
7. Versi package: pakai versi stabil terbaru saat dikerjakan, **catat versi yang dipakai** di laporan fase.
8. Bahasa UI: **Bahasa Indonesia**. Nama class/variabel/komentar: English.

---

## §1 — Struktur Folder Lengkap

```
setel/
├── pubspec.yaml
├── lib/
│   ├── main.dart                      // entry: init Hive, runApp
│   ├── app.dart                       // MaterialApp + router/tab scaffold
│   ├── core/
│   │   ├── constants.dart             // YOUTUBE_API_KEY, batas cache, TTL, dsb
│   │   ├── errors.dart                // AppException
│   │   └── utils.dart                 // formatDuration(), dsb
│   ├── models/
│   │   ├── song.dart                  // HiveType, TANPA field streamUrl
│   │   ├── playlist.dart
│   │   ├── history_entry.dart
│   │   └── search_cache.dart
│   ├── data/
│   │   └── hive_init.dart             // register adapter + open boxes
│   ├── services/
│   │   ├── youtube_service.dart       // kontrak §4.1
│   │   ├── audio_player_service.dart  // kontrak §4.2
│   │   ├── library_service.dart       // kontrak §4.3
│   │   └── cache_service.dart         // kontrak §4.4
│   ├── state/
│   │   ├── providers.dart             // semua Riverpod provider (§6)
│   │   ├── player_controller.dart
│   │   ├── search_controller.dart
│   │   └── library_controller.dart
│   └── ui/
│       ├── screens/
│       │   ├── home_search_screen.dart
│       │   ├── now_playing_screen.dart  // bottom sheet expandable
│       │   ├── library_screen.dart       // tab: Playlist | Favorit | History
│       │   └── settings_screen.dart
│       └── widgets/
│           ├── mini_player.dart
│           ├── song_tile.dart
│           └── queue_sheet.dart
├── android/app/src/main/
│   ├── AndroidManifest.xml            // edit: permission + service (§3)
│   └── kotlin/[package]/MainActivity.kt
└── test/                              // opsional, fase akhir
```

**Aturan struktur:** UI tidak boleh memanggil service langsung — selalu lewat controller/provider di `state/`. Service tidak boleh import widget.

## §2 — pubspec.yaml (dependency awal)

```yaml
dependencies:
  flutter:
    sdk: flutter
  just_audio: <versi stabil terbaru>
  audio_service: <versi stabil terbaru>
  youtube_explode_dart: <versi stabil terbaru>
  dio: <versi stabil terbaru>
  flutter_riverpod: <versi stabil terbaru>
  hive: <versi stabil terbaru>
  hive_flutter: <versi stabil terbaru>
  cached_network_image: <versi stabil terbaru>
  path_provider: <versi stabil terbaru>
  uuid: <versi stabil terbaru>

dev_dependencies:
  flutter_test:
    sdk: flutter
  hive_generator: <versi stabil terbaru>
  build_runner: <versi stabil terbaru>
```

API key YouTube: taruh di `lib/core/constants.dart` sebagai `const String YOUTUBE_API_KEY = 'ISI_DI_SINI';`
(nilai diisi user manual — jangan commit key asli ke repo publik).

## §3 — Konfigurasi Android (wajib untuk background playback)

Di `android/app/src/main/AndroidManifest.xml`, dalam `<manifest>`:

```xml
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK"/>
<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
```

Di dalam `<application>`, daftarkan AudioService (ikuti README versi `audio_service`
yang dipakai — format pastinya mengikuti dokumentasi package tersebut):

```xml
<service android:name="com.ryanheise.audioservice.AudioService"
    android:foregroundServiceType="mediaPlayback"
    android:exported="true">
    <intent-filter>
        <action android:name="android.media.browse.MediaBrowserService" />
    </intent-filter>
</service>
```

**Catatan:** jika README versi terinstal berbeda, ikuti README tersebut — laporkan yang dipakai.

## §4 — Kontrak Interface (JANGAN diubah tanpa konfirmasi user)

### §4.1 YouTubeService

```dart
abstract class YouTubeService {
  /// Cari lagu via YouTube Data API v3. WAJIB cek SearchCache dulu (TTL 24 jam).
  /// 1x search = 100 unit kuota. Error kuota → AppException('Kuota API habis...').
  Future<List<Song>> search(String query);

  /// Resolve stream URL audio-only via youtube_explode_dart.
  /// Pilih muxed/audio-only dengan bitrate tertinggi. JANGAN simpan hasilnya.
  Future<Uri> resolveStreamUrl(String videoId);

  /// Metadata cadangan via iTunes Search API (tanpa key), dipakai jika perlu.
  Future<Song> fetchMetadata(String videoId);
}
```

### §4.2 AudioPlayerService

```dart
enum RepeatMode { off, one, all }

abstract class AudioPlayerService {
  /// Alur: resolveStreamUrl(videoId) → cek cache → just_audio.setUrl → play → recordPlay.
  Future<void> playSong(Song song);
  Future<void> playQueue(List<Song> songs, {int startIndex = 0});
  Future<void> togglePlayPause();
  Future<void> next();
  Future<void> previous();
  Future<void> seek(Duration position);
  Future<void> setShuffle(bool enabled);
  Future<void> setRepeatMode(RepeatMode mode);
  Future<void> addToQueueNext(Song song);   // "play next"

  Stream<PlayerState> get playerState; // isPlaying, position, currentSong, queue, shuffle, repeatMode
}
```

Wajib di atas `audio_service` + `just_audio` agar notifikasi media, lockscreen,
dan tombol headset bekerja otomatis.

### §4.3 LibraryService (Hive)

```dart
abstract class LibraryService {
  Future<Playlist> createPlaylist(String name);
  Future<void> renamePlaylist(String id, String name);
  Future<void> deletePlaylist(String id);
  Future<List<Playlist>> getPlaylists();
  Future<void> addToPlaylist(String playlistId, Song song);
  Future<void> removeFromPlaylist(String playlistId, String videoId);

  Future<void> toggleFavorite(Song song);
  Future<bool> isFavorite(String videoId);
  Future<List<Song>> getFavorites();

  /// FIFO, maks 50 entri. Yang lama dibuang otomatis.
  Future<void> recordPlay(Song song);
  Future<List<HistoryEntry>> getHistory();
}
```

### §4.4 CacheService

```dart
abstract class CacheService {
  /// Kembalikan file cache jika ada & masih valid, null jika tidak.
  Future<File?> getCached(Song song);

  /// Download stream ke file lokal saat lagu diputar. Dipanggil otomatis oleh AudioPlayerService.
  Future<File> cacheSong(Song song, Uri streamUrl);

  /// Hapus file terlama (LRU) jika total > batas. Dipanggil tiap selesai cacheSong.
  Future<void> enforceLimit();

  Future<int> cacheSizeBytes();
  Future<void> clearCache();
}
```

## §5 — Model Data (field wajib, Hive)

```dart
@HiveType(typeId: 0)
class Song {
  @HiveField(0) String videoId;      // Hive key
  @HiveField(1) String title;
  @HiveField(2) String artist;       // nama channel YouTube
  @HiveField(3) int durationMs;
  @HiveField(4) String thumbnailUrl; // hqdefault YouTube
  @HiveField(5) String? cachedPath;  // null jika belum di-cache
  // TIDAK ADA field streamUrl. Titik.
}

@HiveType(typeId: 1)
class Playlist {
  @HiveField(0) String id;           // uuid
  @HiveField(1) String name;
  @HiveField(2) DateTime createdAt;
  @HiveField(3) List<String> songIds; // videoId list
}

@HiveType(typeId: 2)
class HistoryEntry {
  @HiveField(0) String videoId;
  @HiveField(1) DateTime playedAt;
}

@HiveType(typeId: 3)
class SearchCache {
  @HiveField(0) String query;        // key: lowercase + trim
  @HiveField(1) List<String> videoIds;
  @HiveField(2) DateTime cachedAt;   // TTL 24 jam
}

@HiveType(typeId: 4)
class Settings {
  @HiveField(0) int cacheLimitMB;    // default 500
}
```

Box names: `songs`, `playlists`, `favorites` (simpan videoId set), `history`,
`search_cache`, `settings`. Generate adapter via `build_runner`.

## §6 — Providers (Riverpod) yang Wajib Ada

```dart
// services
youtubeServiceProvider, audioPlayerServiceProvider,
libraryServiceProvider, cacheServiceProvider
// controllers (StateNotifier)
playerControllerProvider  // currentSong, isPlaying, position, queue, shuffle, repeatMode
searchControllerProvider  // query, results, isLoading, error
libraryControllerProvider // playlists, favorites, history (+ refresh methods)
settingsControllerProvider // cacheLimitMB
```

## §7 — Task Per Fase + Acceptance Criteria

### Fase 0 — Fondasi
- [ ] `flutter create setel` (package name bebas, mis. `com.bengkel.setel`)
- [ ] pubspec.yaml sesuai §2; `flutter pub get` sukses
- [ ] `main.dart` + `hive_init.dart`: semua box kebuka tanpa error
- [ ] AndroidManifest sesuai §3
- [ ] **AC:** app terbuka < 2 detik, `flutter analyze` 0 masalah, audio_service ter-init (log)

### Fase 1 — Search + Play + Now Playing (inti)
- [ ] `YouTubeService.search()` + SearchCache (TTL 24 jam)
- [ ] `home_search_screen.dart`: input → list hasil (`song_tile.dart`)
- [ ] `AudioPlayerService.playSong()` (resolve → setUrl → play)
- [ ] `now_playing_screen.dart`: play/pause/next/prev/seek/shuffle/repeat + artwork
- [ ] `mini_player.dart` persisten
- [ ] **AC:** cari & putar lagu < 10 detik dari app dibuka; seek & kontrol < 200ms

### Fase 2 — Background + Antrean
- [ ] Notifikasi media muncul otomatis (audio_service); test minimize + layar mati
- [ ] Tombol headset: play/pause/next berfungsi
- [ ] `playQueue`, `addToQueueNext`, `queue_sheet.dart` (reorder via drag)
- [ ] **AC:** 1 jam nonstop layar mati tanpa putus (test manual, catat hasil)

### Fase 3 — Library Lokal
- [ ] `LibraryService` full (§4.3) + `library_screen.dart` (3 tab)
- [ ] Favorit toggle dari `song_tile` & now playing
- [ ] History FIFO 50
- [ ] **AC:** buat playlist → tambah 3 lagu → restart app → playlist utuh

### Fase 4 — Offline Cache + Poles
- [ ] `CacheService` full (§4.4): auto-cache saat play, LRU enforce, batas adjustable
- [ ] `settings_screen.dart`: batas cache, hapus cache, info kuota, tentang
- [ ] Sleep timer (P1 PRD, naik ke fase ini — user butuh)
- [ ] Rapikan UI: empty states, error SnackBar, loading shimmer
- [ ] **AC PRD §16:** semua 5 kriteria sukses terpenuhi

## §8 — Konvensi Kode

- Error: try/catch di service → lempar `AppException(pesanUser)` → UI tampilkan SnackBar. Jangan biarkan exception mentah ke user.
- Dilarang `print()` — pakai `debugPrint`.
- Setiap service punya 1 file test minimal? Opsional — prioritaskan fitur jalan.
- Komentar: jelaskan *kenapa*, bukan *apa*.

## §9 — Checklist Audit (diisi Muse setelah tiap fase)

- [ ] Aturan emas: grep `streamUrl` di `models/` & Hive boxes → harus NOL hasil
- [ ] Permission Android minimal (§3) — tidak ada izin aneh
- [ ] Stream yang dipakai audio-only (bukan video) — hemat baterai/kuota
- [ ] SearchCache aktif — query ulang tidak makan kuota
- [ ] LRU cache: isi cache > batas → file terlama terhapus otomatis
- [ ] `flutter analyze` 0 error/warning (laporan Gemini dilampirkan)
- [ ] Kriteria sukses PRD §16 per fase terpenuhi
- [ ] Tidak ada API key / secret ter-commit (cek `constants.dart` hanya placeholder)

---

## §10 — Prompt Siap Tempel untuk Gemini

> Tempel ini sebagai pesan pertama ke Gemini di Antigravity, dengan kedua file
> (`PRD-musik-pribadi.md` dan file ini) tersedia di workspace:

```
Kamu adalah Flutter developer senior. Kita akan membangun aplikasi Android
"Setel" — aplikasi streaming musik pribadi ala Joox, sumber katalog YouTube.

CARA KERJA:
1. Baca PRD-musik-pribadi.md sampai paham, lalu BUILD-SPEC ini sampai habis.
2. Kerjakan per fase (§7), mulai dari Fase 0. Satu fase selesai = semua
   checklist + acceptance criteria fase itu terpenuhi.
3. Setiap fase selesai: jalankan `flutter analyze` (harus 0 error/warning),
   lalu laporkan: file yang dibuat/diubah, versi package yang dipakai,
   dan hasil uji acceptance criteria.
4. Jangan lanjut ke fase berikutnya sebelum aku bilang OK.

ATURAN KERAS (pelanggaran = kerjaan ditolak):
- Jangan pernah menyimpan stream URL YouTube ke database. Simpan hanya
  videoId + metadata. Stream URL di-resolve ulang setiap kali play.
- Jangan ubah kontrak interface di §4 tanpa izinku.
- Jangan tambah dependency di luar §2 tanpa izinku.
- UI berbahasa Indonesia. Kode/komentar berbahasa Inggris.
- Error selalu dibungkus AppException dengan pesan yang dimengerti user.

Mulai dari Fase 0 sekarang. Laporkan dulu rencanamu dalam 5 baris,
lalu eksekusi.
```

---

*Dokumen ini + PRD = satu-satunya sumber kebenaran. Kalau keduanya bertentangan, PRD menang untuk "apa", BUILD SPEC menang untuk "bagaimana".*
