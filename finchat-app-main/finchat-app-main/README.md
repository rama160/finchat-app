# Finchat AI 💰🤖

Aplikasi pencatat keuangan pribadi berbasis Flutter — **offline-first**, dengan
asisten AI (Gemini) untuk scan struk dan chat keuangan, laporan lengkap, dan
sinkronisasi opsional ke Google Sheets sebagai cloud backup.

## Fitur

- **Offline-first**: semua transaksi tersimpan di SQLite lokal (`sqflite`),
  aplikasi tetap berfungsi penuh tanpa internet untuk pencatatan manual dan
  laporan.
- **Scan Struk (Gemini Vision OCR)**: foto struk belanja → otomatis terisi
  kategori, deskripsi, nominal, dan merchant.
- **Chat Interface + Input Transaksi Natural Language**: ketik bebas seperti
  *"beli kopi 20000"* atau *"gaji bulan ini 5000000"* dan Gemini akan mengurai
  lalu menyimpannya sebagai transaksi.
- **AI Financial Assistant**: tanya seputar keuangan kamu, mis. *"berapa
  pengeluaran saya bulan ini?"* — dijawab berdasarkan data transaksi asli di
  perangkat.
- **Dashboard**: ringkasan pemasukan/pengeluaran/saldo bulan berjalan +
  grafik pie pengeluaran per kategori + transaksi terbaru.
- **Laporan**: Harian, Per Tanggal, Rentang Tanggal, dan Bulanan — masing-masing
  bisa langsung **Export ke PDF**.
- **Sinkronisasi Google Sheets**: transaksi yang belum tersinkron dikirim ke
  Google Sheets saat online, sebagai cloud backup sederhana tanpa OAuth di
  aplikasi mobile.

## Struktur Proyek

```
lib/
  main.dart                    # Entry point + MainShell (bottom navigation)
                                # HomeScreen di dalamnya = kode asli (tidak diubah)
  models/
    transaction_model.dart     # Model transaksi asli (tidak diubah)
    chat_message_model.dart    # BARU — riwayat chat AI
  services/
    database_helper.dart       # SQLite asli + method baru (additive only)
    gemini_service.dart        # BARU — chat AI & parsing transaksi bahasa natural
    sheets_service.dart        # BARU — sinkron ke Google Sheets
    pdf_service.dart           # BARU — export laporan ke PDF
    prefs_service.dart         # BARU — penyimpanan API key & URL Sheets
  screens/
    dashboard_screen.dart      # BARU
    chat_screen.dart           # BARU
    reports_screen.dart        # BARU
    settings_screen.dart       # BARU
```

> Catatan penting: kode asli (`HomeScreen`, `TransactionModel`, skema tabel
> `transactions`, dan alur scan struk) **tidak diubah sama sekali** — fitur
> baru murni ditambahkan di file/kelas terpisah. Satu-satunya penyesuaian
> kecil pada file asli: `main()` diberi `initializeDateFormatting('id_ID')`
> agar format tanggal Indonesia bisa dipakai, dan API key yang disimpan lewat
> dialog `HomeScreen` kini juga tersimpan ke `PrefsService` agar bisa dipakai
> bersama oleh halaman Chat AI & Pengaturan.

## Setup

### 1. Gemini API Key
Buka halaman **Pengaturan** di aplikasi → masukkan API key dari
[Google AI Studio](https://aistudio.google.com/app/apikey) → **Simpan**.
Dipakai untuk Scan Struk dan Chat AI.

### 2. Google Sheets sebagai Cloud (opsional)
1. Buat Google Sheet baru.
2. **Extensions → Apps Script**, hapus isi default, tempel:

```javascript
function doPost(e) {
  const sheet = SpreadsheetApp.getActiveSpreadsheet().getActiveSheet();
  const data = JSON.parse(e.postData.contents);
  sheet.appendRow([
    data.id, data.chat_id, data.transaction_date, data.transaction_time,
    data.type, data.category, data.description, data.amount,
    data.payment_method, data.merchant, data.notes, data.source
  ]);
  return ContentService.createTextOutput(JSON.stringify({status: 'ok'}))
      .setMimeType(ContentService.MimeType.JSON);
}
```

3. **Deploy → New deployment → Web app**. Execute as: *Me*. Who has access:
   *Anyone*. Klik **Deploy** dan salin URL Web App yang diberikan.
4. Tempel URL tersebut di halaman **Pengaturan** aplikasi, lalu tekan
   **Sinkron Sekarang**.

## Build APK

Repo ini sudah dilengkapi GitHub Actions (`.github/workflows/build_apk.yml`)
yang otomatis build APK release setiap push ke `main`/`master`, atau bisa
dijalankan manual lewat tab **Actions → Run workflow**. Hasil APK bisa
diunduh dari bagian **Artifacts** pada run tersebut.

Build manual secara lokal:

```bash
flutter pub get
flutter build apk --release
```

## Izin Android

Karena aplikasi memanggil internet (Gemini API & Google Sheets), pastikan
`android/app/src/main/AndroidManifest.xml` (dibuat otomatis oleh
`flutter create .`) memiliki:

```xml
<uses-permission android:name="android.permission.INTERNET" />
```

Jika belum ada, tambahkan baris tersebut secara manual sebelum build release.
