# Finchat AI 4.1

Upgrade dari V3/V4 dengan tetap mempertahankan struktur utama dan alur offline-first.

## Perubahan

- Transaksi: Edit dan Hapus.
- Transaksi: input suara Bahasa Indonesia -> teks -> parser transaksi yang sama.
- Dashboard dihapus dari navigasi karena fungsi ringkasannya dipindahkan/diwakili Laporan.
- Laporan: grafik arus kas harian, kategori berdasarkan jumlah transaksi, pengeluaran terbesar sesuai filter, dan tabel detail transaksi.
- Parser: "pemasukan 1 juta" sekarang selalu menjadi `income`; "gajian 5 juta" menjadi pemasukan kategori Gaji.
- Google Sheets: sinkron batch, menangani redirect Apps Script, validasi respons, update transaksi hasil edit, dan sinkron penghapusan.
- Google Sheets: pemulihan otomatis saat database lokal kosong setelah reinstall.
- SQLite naik ke versi 3 secara additive: tabel lama tidak diubah; ditambah tabel tombstone untuk penghapusan cloud.
- Speech recognition memakai `speech_to_text`.

## Google Sheets

Gunakan `server/google_apps_script/Code.gs`.

Deploy sebagai Web App:
1. Google Sheet -> Extensions -> Apps Script.
2. Salin isi `Code.gs`.
3. Deploy -> New deployment -> Web app.
4. Execute as: Me.
5. Who has access: Anyone.
6. Salin URL `/exec` ke Pengaturan Finchat.
7. Tekan **Tes Koneksi**.
8. Tekan **Sinkron Sekarang** untuk transaksi lokal yang belum tersinkron.

Setelah transaksi tersinkron, reinstall aplikasi dapat memulihkan transaksi melalui **Pulihkan Data**. Aplikasi juga mencoba pemulihan otomatis ketika database lokal kosong.

## Build Android

Workflow GitHub Actions akan:
- membuat folder Android dengan `flutter create . --platforms=android`;
- memasang minimum SDK 23;
- menambahkan permission mikrofon dan package visibility untuk speech recognition;
- menjalankan `flutter analyze` dan `flutter test`;
- membuat release APK.

## Catatan

Data lokal SQLite memang ikut terhapus oleh Android ketika aplikasi di-uninstall. Karena itu perlindungan terhadap uninstall dilakukan dengan backup cloud melalui Google Sheets. Sebelum uninstall, pastikan **Sinkron Sekarang** berhasil dan jumlah transaksi yang tersinkron bukan 0 karena memang tidak ada transaksi pending.

File `server/google_apps_script/Code.gs` harus dipasang ulang hanya jika membuat deployment Apps Script baru; URL deployment yang sudah ada tetap dapat digunakan.


## Migrasi aman dari V3.1

Karena signing key APK V3.1 tidak tersedia, jangan mengandalkan instalasi V4 sebagai update langsung. Di V3.1, gunakan Google Sheets sebagai backup jika tersedia atau ekspor/backup data sebelum uninstall. Pada V4.1.2 tersedia menu Pengaturan > Backup & Migrasi > Backup Data untuk membuat file JSON yang berada di luar storage aplikasi. Setelah instalasi ulang, pilih Restore Backup. Restore menolak database yang masih berisi transaksi agar tidak menimpa data secara tidak sengaja.

Untuk build berikutnya, application ID harus dipertahankan sebagai `com.example.finchat_app`. Signing key baru tidak dapat membuat APK baru menjadi update langsung terhadap APK lama yang ditandatangani dengan key yang hilang.


## Jalur migrasi V3.1 tanpa signing key lama

1. **Jangan uninstall V3.1 terlebih dahulu.**
2. Di Google Apps Script, gunakan `server/google_apps_script/Code.gs` dari V4.1.2. Script ini menerima format request lama V3.1 maupun format batch V4.1.2 dan menggunakan ID transaksi sebagai kunci update/deduplikasi.
3. Di V3.1, masukkan URL Web App yang sama dan tekan `Sinkron Sekarang`. Pastikan jumlah transaksi yang tersinkron lebih dari 0 dan periksa tab `Transactions` di Google Sheets.
4. Setelah data di Sheets lengkap, V3.1 boleh di-uninstall. **Data lokal V3.1 akan terhapus pada tahap ini, tetapi salinan sudah berada di Sheets.**
5. Install V4.1.2. Masukkan URL Web App yang sama pada Pengaturan.
6. Tekan `Pulihkan Data`. V4.1.2 mempertahankan ID asli dari Sheets sehingga edit berikutnya tetap memperbarui baris yang sama.
7. Setelah transaksi kembali, gunakan `Backup Data` untuk membuat file JSON sebagai backup offline tambahan.

Karena signing key V3.1 tidak tersedia, APK V4.1.2 tidak dapat dijamin sebagai update in-place terhadap APK lama. Jangan uninstall V3.1 sampai langkah sinkronisasi dan verifikasi Sheets berhasil.
