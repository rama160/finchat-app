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
