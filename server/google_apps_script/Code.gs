/**
 * FINCHAT AI - Google Sheets Web App API
 * Kompatibel dengan Finchat V3.1 dan V4.x.
 *
 * Fungsi API:
 * GET  /exec?action=health
 * GET  /exec?action=list
 * POST single transaction (V3.1)
 * POST {action:'sync', transactions:[...]} (V4.x)
 * POST {action:'delete', ids:[...]} (V4.x)
 */

var SHEET_NAMES = ['Transaksi', 'Transactions'];
var HEADERS = [
  'id', 'chat_id', 'transaction_date', 'transaction_time', 'type',
  'category', 'description', 'amount', 'payment_method', 'merchant',
  'notes', 'source'
];

function jsonResponse_(data) {
  return ContentService.createTextOutput(JSON.stringify(data))
    .setMimeType(ContentService.MimeType.JSON);
}

function getTransactionSheet_() {
  var ss = SpreadsheetApp.getActiveSpreadsheet();
  var sheet = ss.getSheetByName('Transaksi') || ss.getSheetByName('Transactions');
  if (!sheet) sheet = ss.insertSheet('Transaksi');
  ensureHeaders_(sheet);
  return sheet;
}

function ensureHeaders_(sheet) {
  if (sheet.getLastRow() === 0) {
    sheet.getRange(1, 1, 1, HEADERS.length).setValues([HEADERS]);
  }
}

function normalizeTransaction_(data) {
  return {
    id: String(data.id == null ? '' : data.id).trim(),
    chat_id: String(data.chat_id == null ? '' : data.chat_id),
    transaction_date: String(data.transaction_date == null ? '' : data.transaction_date),
    transaction_time: String(data.transaction_time == null ? '' : data.transaction_time),
    type: String(data.type == null ? 'expense' : data.type),
    category: String(data.category == null ? 'Lainnya' : data.category),
    description: String(data.description == null ? 'Transaksi' : data.description),
    amount: Number(data.amount || 0),
    payment_method: String(data.payment_method == null ? 'Cash' : data.payment_method),
    merchant: String(data.merchant == null ? '' : data.merchant),
    notes: String(data.notes == null ? '' : data.notes),
    source: String(data.source == null ? 'manual' : data.source)
  };
}

function findRowById_(sheet, id) {
  var lastRow = sheet.getLastRow();
  if (lastRow <= 1) return 0;
  var values = sheet.getRange(2, 1, lastRow - 1, 1).getValues();
  var target = String(id).trim();
  for (var i = 0; i < values.length; i++) {
    if (String(values[i][0]).trim() === target) return i + 2;
  }
  return 0;
}

function upsertTransaction_(sheet, tx) {
  if (!tx.id) throw new Error('Transaction ID kosong.');
  var row = [
    tx.id, tx.chat_id, tx.transaction_date, tx.transaction_time, tx.type,
    tx.category, tx.description, tx.amount, tx.payment_method, tx.merchant,
    tx.notes, tx.source
  ];
  var existingRow = findRowById_(sheet, tx.id);
  if (existingRow > 0) {
    sheet.getRange(existingRow, 1, 1, HEADERS.length).setValues([row]);
  } else {
    sheet.getRange(sheet.getLastRow() + 1, 1, 1, HEADERS.length).setValues([row]);
  }
}

function doGet(e) {
  try {
    var action = e && e.parameter && e.parameter.action
      ? String(e.parameter.action).toLowerCase()
      : 'health';

    if (action === 'health') {
      return jsonResponse_({
        result: 'success', status: 'ok',
        service: 'Finchat AI Google Sheets API',
        timestamp: new Date().toISOString()
      });
    }

    if (action === 'list' || action === 'transactions') {
      var sheet = getTransactionSheet_();
      var lastRow = sheet.getLastRow();
      if (lastRow <= 1) {
        return jsonResponse_({result: 'success', status: 'ok', transactions: [], count: 0});
      }
      var values = sheet.getRange(2, 1, lastRow - 1, HEADERS.length).getValues();
      var transactions = values.filter(function(row) {
        return row[0] !== '' && row[0] != null;
      }).map(function(row) {
        var tx = {};
        HEADERS.forEach(function(h, i) { tx[h] = row[i]; });
        return tx;
      });
      return jsonResponse_({
        result: 'success', status: 'ok',
        transactions: transactions, count: transactions.length
      });
    }

    return jsonResponse_({result: 'success', status: 'ok'});
  } catch (err) {
    return jsonResponse_({result: 'error', status: 'error', message: String(err)});
  }
}

function doPost(e) {
  try {
    if (!e || !e.postData || !e.postData.contents) {
      return jsonResponse_({result: 'error', status: 'error', message: 'Body request kosong.'});
    }

    var data = JSON.parse(e.postData.contents);
    var sheet = getTransactionSheet_();

    // V4.x delete.
    if (String(data.action || '').toLowerCase() === 'delete' && Array.isArray(data.ids)) {
      var deletedIds = [];
      for (var i = data.ids.length - 1; i >= 0; i--) {
        var id = String(data.ids[i] == null ? '' : data.ids[i]).trim();
        if (!id) continue;
        var row = findRowById_(sheet, id);
        if (row > 0) {
          sheet.deleteRow(row);
          deletedIds.push(id);
        }
      }
      SpreadsheetApp.flush();
      return jsonResponse_({
        result: 'success', status: 'ok', action: 'delete',
        deleted: deletedIds.length, deleted_ids: deletedIds, ids: deletedIds
      });
    }

    // V4.x batch sync.
    if (String(data.action || '').toLowerCase() === 'sync' && Array.isArray(data.transactions)) {
      var confirmedIds = [];
      var failedIds = [];
      data.transactions.forEach(function(item) {
        try {
          var tx = normalizeTransaction_(item || {});
          if (!tx.id) throw new Error('ID kosong');
          upsertTransaction_(sheet, tx);
          confirmedIds.push(tx.id);
        } catch (err) {
          failedIds.push(item && item.id != null ? String(item.id) : '');
        }
      });
      SpreadsheetApp.flush();
      return jsonResponse_({
        result: 'success', status: 'ok', action: 'sync',
        received: data.transactions.length,
        synced: confirmedIds.length,
        confirmed_ids: confirmedIds,
        ids: confirmedIds,
        failed_ids: failedIds
      });
    }

    // V3.1 single transaction.
    if (data.id != null) {
      var single = normalizeTransaction_(data);
      upsertTransaction_(sheet, single);
      SpreadsheetApp.flush();
      return jsonResponse_({
        result: 'success', status: 'ok', action: 'sync', id: single.id,
        synced: 1, confirmed_ids: [single.id], ids: [single.id]
      });
    }

    return jsonResponse_({result: 'error', status: 'error', message: 'Format data tidak dikenali.'});
  } catch (err) {
    return jsonResponse_({result: 'error', status: 'error', message: String(err)});
  }
}

/** Fungsi manual untuk memastikan Sheet dapat ditulis. */
function testFinchatSheet() {
  var sheet = getTransactionSheet_();
  var testId = 'TEST_' + new Date().getTime();
  upsertTransaction_(sheet, normalizeTransaction_({
    id: testId,
    chat_id: 'test',
    transaction_date: Utilities.formatDate(new Date(), Session.getScriptTimeZone(), 'yyyy-MM-dd'),
    transaction_time: Utilities.formatDate(new Date(), Session.getScriptTimeZone(), 'HH:mm:ss'),
    type: 'expense', category: 'Test', description: 'Test koneksi Finchat', amount: 1000,
    payment_method: 'Cash', merchant: 'Test', notes: 'Data test dari Apps Script', source: 'apps_script_test'
  }));
  SpreadsheetApp.flush();
  SpreadsheetApp.getUi().alert('Berhasil! Transaksi test berhasil ditambahkan. ID: ' + testId);
}

/** FUNGSI: export tab Dashboard Laporan menjadi PDF. */
function exportDashboardToPDF() {
  var ss = SpreadsheetApp.getActiveSpreadsheet();
  var sheet = ss.getSheetByName('Dashboard Laporan');
  if (!sheet) {
    SpreadsheetApp.getUi().alert("Error: Tab bernama 'Dashboard Laporan' tidak ditemukan!");
    return;
  }
  var url = ss.getUrl().replace(/edit$/, '') +
    'export?exportFormat=pdf&format=pdf&size=A4&portrait=true&fitw=true&gridlines=false&gid=' +
    sheet.getSheetId();
  var html = HtmlService.createHtmlOutput(
    '<script>window.open("' + url + '");google.script.host.close();</script>'
  ).setWidth(300).setHeight(100);
  SpreadsheetApp.getUi().showModalDialog(html, 'Membuka PDF Laporan...');
}

function onOpen() {
  SpreadsheetApp.getUi().createMenu('📊 Menu Laporan')
    .addItem('📄 Unduh Laporan PDF', 'exportDashboardToPDF')
    .addItem('🔄 Refresh Dashboard', 'refreshDashboard')
    .addItem('🧪 Test Finchat API', 'testFinchatSheet')
    .addToUi();
}

function refreshDashboard() {
  SpreadsheetApp.flush();
  SpreadsheetApp.getUi().alert('Dashboard berhasil diperbarui!');
}
