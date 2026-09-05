/**
 * Finchat AI - Google Apps Script backend untuk Google Sheets.
 *
 * Cara pasang:
 * 1. Buka Google Sheet -> Extensions -> Apps Script.
 * 2. Tempel file ini ke Code.gs.
 * 3. Deploy -> New deployment -> Web app.
 * 4. Execute as: Me.
 * 5. Who has access: Anyone.
 * 6. Salin URL /exec ke Pengaturan Finchat.
 *
 * Struktur kolom dibuat otomatis. ID transaksi dipakai sebagai kunci deduplikasi,
 * sehingga sinkronisasi ulang tidak membuat baris duplikat.
 */

const SHEET_NAME = 'Transactions';
const HEADERS = [
  'id',
  'chat_id',
  'transaction_date',
  'transaction_time',
  'type',
  'category',
  'description',
  'amount',
  'payment_method',
  'merchant',
  'notes',
  'source'
];

function getSheet_() {
  const ss = SpreadsheetApp.getActiveSpreadsheet();
  let sheet = ss.getSheetByName(SHEET_NAME);
  if (!sheet) sheet = ss.insertSheet(SHEET_NAME);

  if (sheet.getLastRow() === 0) {
    sheet.appendRow(HEADERS);
  } else {
    const current = sheet.getRange(1, 1, 1, HEADERS.length).getValues()[0];
    const same = HEADERS.every((h, i) => String(current[i] || '') === h);
    if (!same) {
      sheet.insertRowBefore(1);
      sheet.getRange(1, 1, 1, HEADERS.length).setValues([HEADERS]);
    }
  }
  return sheet;
}

function json_(data) {
  return ContentService
    .createTextOutput(JSON.stringify(data))
    .setMimeType(ContentService.MimeType.JSON);
}

function doGet(e) {
  const action = (e && e.parameter && e.parameter.action) || 'health';
  const sheet = getSheet_();

  if (action === 'health') {
    return json_({
      status: 'ok',
      message: 'Finchat Google Sheets backend aktif',
      sheet: SHEET_NAME
    });
  }

  if (action === 'list') {
    const lastRow = sheet.getLastRow();
    if (lastRow <= 1) {
      return json_({ status: 'ok', transactions: [] });
    }

    const values = sheet
      .getRange(2, 1, lastRow - 1, HEADERS.length)
      .getValues();

    const transactions = values
      .filter(row => row[0] !== '' && row[0] != null)
      .map(row => {
        const item = {};
        HEADERS.forEach((header, index) => {
          item[header] = row[index];
        });
        return item;
      });

    return json_({ status: 'ok', transactions: transactions });
  }

  return json_({ status: 'ok', message: 'Finchat backend aktif' });
}

function doPost(e) {
  try {
    if (!e || !e.postData || !e.postData.contents) {
      return json_({ status: 'error', message: 'Body request kosong.' });
    }

    const payload = JSON.parse(e.postData.contents);
    const sheet = getSheet_();

    if (payload.action === 'delete') {
      const ids = Array.isArray(payload.ids) ? payload.ids.map(String) : [];
      const lastRow = sheet.getLastRow();
      const removed = [];
      if (lastRow > 1 && ids.length > 0) {
        const values = sheet.getRange(2, 1, lastRow - 1, HEADERS.length).getValues();
        for (let i = values.length - 1; i >= 0; i--) {
          if (ids.indexOf(String(values[i][0])) !== -1) {
            removed.push(Number(values[i][0]));
            sheet.deleteRow(i + 2);
          }
        }
      }
      return json_({ status: 'ok', ids: removed });
    }

    const transactions = Array.isArray(payload.transactions)
      ? payload.transactions
      : [payload];

    const lastRow = sheet.getLastRow();

    // Index ID yang sudah ada untuk mencegah duplikasi.
    const existing = {};
    if (lastRow > 1) {
      const ids = sheet.getRange(2, 1, lastRow - 1, 1).getValues();
      ids.forEach((row, i) => {
        if (row[0] !== '' && row[0] != null) {
          existing[String(row[0])] = i + 2;
        }
      });
    }

    const syncedIds = [];

    transactions.forEach(tx => {
      if (!tx || tx.id == null) return;

      const id = String(tx.id);
      const row = [
        tx.id,
        tx.chat_id || 'local_user',
        tx.transaction_date || '',
        tx.transaction_time || '',
        tx.type || 'expense',
        tx.category || 'Lainnya',
        tx.description || 'Transaksi',
        Number(tx.amount || 0),
        tx.payment_method || 'Cash',
        tx.merchant || '',
        tx.notes || '',
        tx.source || 'manual'
      ];

      if (existing[id]) {
        // Update jika transaksi diedit di HP.
        sheet.getRange(existing[id], 1, 1, HEADERS.length).setValues([row]);
      } else {
        sheet.appendRow(row);
        existing[id] = sheet.getLastRow();
      }

      syncedIds.push(Number(tx.id));
    });

    return json_({
      status: 'ok',
      synced: syncedIds.length,
      ids: syncedIds
    });
  } catch (err) {
    return json_({
      status: 'error',
      message: String(err && err.message ? err.message : err)
    });
  }
}
