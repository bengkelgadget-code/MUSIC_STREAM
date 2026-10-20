# Setel — Personal Music Streaming App

Aplikasi streaming musik pribadi berbasis Flutter untuk platform Android dengan katalog YouTube, pemutaran audio di latar belakang (background playback), manajemen antrean, library lokal (playlist, favorit, riwayat), cache stream offline otomatis berbatas kapasitas (LRU eviction), sleep timer, dan pembaruan OTA (Over-The-Air) otomatis via GitHub Releases.

---

## 🔐 Panduan Setup Signing Keystore & GitHub Secrets (Wajib untuk OTA)

> [!IMPORTANT]
> Sistem operasi Android mewajibkan **seluruh pembaruan aplikasi (update APK)** ditandatangani dengan sertifikat kunci (*keystore*) yang **sama persis**. Jika kunci penandatanganan berubah antar-rilis, sistem Android akan menolak pembaruan dengan galat `INSTALL_FAILED_UPDATE_INCOMPATIBLE`.
> 
> **Peringatan Keamanan:** Jangan pernah meng-commit file `.jks`, `.keystore`, atau file `key.properties` ke dalam git repository publik maupun privat! File tersebut sudah dimasukkan ke `.gitignore`.

### Langkah 1: Buat Keystore Rilis Menggunakan `keytool`

Jalankan perintah berikut di PowerShell atau Terminal laptop Anda (pastikan JDK/Java telah terpasang):

```bash
keytool -genkey -v -keystore setel-release.jks -keyalg RSA -keysize 2048 -validity 10000 -alias setel_key
```

Anda akan diminta mengisi:
- Password Keystore (catat password ini)
- Informasi identitas diri/organisasi (nama, unit, dsb.)
- Password Kunci Alias (bisa disamakan dengan password keystore)

File `setel-release.jks` akan terbentuk di direktori aktif Anda. **Simpan dan cadangkan file ini di tempat yang aman!**

---

### Langkah 2: Konversi File Keystore Menjadi String Base64

Keystore berupa biner perlu diubah menjadi teks Base64 agar dapat disimpan dengan aman sebagai *Secret* di GitHub Actions:

- **Windows PowerShell:**
  ```powershell
  [Convert]::ToBase64String([IO.File]::ReadAllBytes("setel-release.jks")) | Set-Clipboard
  ```
  *(String Base64 otomatis disalin ke clipboard Anda).*

- **Linux / macOS:**
  ```bash
  base64 -w 0 setel-release.jks
  ```

---

### Langkah 3: Daftarkan 4 GitHub Secrets di Repositori

Buka repositori Anda di browser GitHub:
1. Klik menu tab **Settings**.
2. Di panel kiri, buka **Secrets and variables** > **Actions**.
3. Klik tombol hijau **New repository secret**.
4. Tambahkan **4 secrets** berikut:

| Nama Secret | Deskripsi / Nilai | Contoh Nilai |
|---|---|---|
| `KEYSTORE_BASE64` | Seluruh isi teks Base64 dari file `setel-release.jks` (hasil Langkah 2) | `MIIDvTCCAqWgAwIBAgIE...` |
| `KEYSTORE_PASSWORD` | Password keystore yang Anda masukkan saat `keytool` | `password_keystore_anda` |
| `KEY_ALIAS` | Nama alias kunci yang Anda gunakan saat `keytool` | `setel_key` |
| `KEY_PASSWORD` | Password dari alias kunci | `password_kunci_anda` |

---

### Langkah 4: Alur Rilis & Update Otomatis (OTA)

Setelah 4 Secrets di atas dikonfigurasi:
1. Setiap kali versi di `setel/pubspec.yaml` dinaikkan (misal `version: 1.0.1+2`) dan di-push ke branch `main`, GitHub Actions akan:
   - Men-decode `KEYSTORE_BASE64` menjadi `setel-release.jks`.
   - Mengisi konfigurasi penandatanganan pada `key.properties`.
   - Melakukan kompilasi `flutter build apk --release` bertanda tangan resmi.
   - Mengunggah file `Setel.apk` ke **GitHub Releases**.
   - Memperbarui file metadata `version.json` di repositori secara otomatis.
2. Pengguna yang membuka aplikasi Setel di perangkat Android akan langsung menerima dialog notifikasi pembaruan OTA dan dapat mengunduh serta memperbarui aplikasi secara otomatis dengan 1 kali klik.

---

## 🛠️ Pengembangan Lokal (Development & Debug)

Untuk menjalankan atau menguji aplikasi di laptop secara lokal tanpa keystore rilis:
- Konfigurasi Gradle pada [`setel/android/app/build.gradle.kts`](setel/android/app/build.gradle.kts) secara otomatis mendeteksi keberadaan file `key.properties`.
- Jika `key.properties` **tidak ada**, sistem secara otomatis menggunakan kunci debug bawaan (*fallback* ke debug signing) sehingga perintah `flutter run` dan pengujian unit tetap berjalan normal tanpa kendala.

```bash
# Menjalankan static analysis
cd setel
flutter analyze

# Menjalankan unit tests
flutter test

# Menjalankan aplikasi di emulator / device fisik
flutter run
```
