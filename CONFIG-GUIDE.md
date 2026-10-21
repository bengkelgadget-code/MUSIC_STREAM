# Panduan Mengubah Kategori Playlist Beranda dari HP / Browser

Fitur **Kategori Server-Driven** pada aplikasi Setel memungkinkan Anda mengubah, menambah, menghapus, atau mengatur ulang kartu playlist di Beranda tanpa perlu update aplikasi (OTA) atau merilis ulang kode.

---

### Cara Mengubah dari HP / Komputer:

1. **Buka File Konfigurasi di GitHub:**
   - Buka browser di HP/laptop Anda dan kunjungi:  
     `https://github.com/bengkelgadget-code/MUSIC_STREAM/blob/main/setel/assets/discovery_categories.json`

2. **Edit File:**
   - Tekan ikon pensil (**Edit this file**) di pojok kanan atas tampilan file GitHub.

3. **Format Data Kategori:**
   File berupa JSON dengan format:
   ```json
   {
     "version": 1,
     "categories": [
       {
         "id": "top-hits-indo",
         "title": "Top Hits Indonesia",
         "group": "INDO",
         "query": "lagu pop indonesia terbaru official video",
         "icon": "trending_up"
       },
       {
         "id": "top-hits-global",
         "title": "Top Hits Global",
         "group": "MANCA",
         "query": "top hits global official music video",
         "icon": "public"
       }
     ]
   }
   ```

   **Penjelasan Bidang:**
   - `id`: Teks unik (slug huruf kecil dengan tanda hubung), contoh `"koplo-ambyar"`.
   - `title`: Judul kartu yang tampil di aplikasi, contoh `"Koplo Ambyar"`.
   - `group`: `"INDO"` (muncul di baris Playlist Indo) atau `"MANCA"` (muncul di baris Playlist Manca).
   - `query`: Kata kunci pencarian YouTube untuk playlist tersebut, contoh `"lagu koplo ambyar terbaru"`.
   - `icon`: Ikon Material Icons, contoh: `trending_up`, `celebration`, `music_note`, `coffee`, `favorite_border`, `public`, `flash_on`, `headset_mic`, `speaker`, `spa`, dll.

4. **Simpan / Commit Perubahan:**
   - Gulir ke bawah halaman GitHub.
   - Tekan tombol hijau **Commit changes...** lalu konfirmasi.

5. **Melihat Perubahan di Aplikasi Setel:**
   - Buka aplikasi **Setel** di HP Anda.
   - Di halaman Beranda pada seksi **Playlist Indo Terbaik**, tekan ikon **Refresh** (🔄) di pojok kanan header.
   - Kartu playlist baru akan langsung muncul seketika!
   - Jika tidak ditekan tombol refresh, kartu akan diperbarui otomatis maksimal dalam 24 jam.

---

### Catatan Keamanan Offline:
- Jika HP Anda sedang offline atau tidak ada internet, aplikasi tetap aman menggunakan cache lokal dan file bawaan tanpa crash.
- Jika ada kesalahan penulisan JSON di GitHub (misalnya kurung kurawal kurang), aplikasi otomatis mendeteksi dan tetap menggunakan data cadangan yang aman.
