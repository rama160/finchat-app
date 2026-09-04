import 'package:flutter_test/flutter_test.dart';
import 'package:finchat_app/services/transaction_parser.dart';

void main() {
  test('memisahkan transaksi yang dipisahkan koma', () {
    final result = TransactionParser.parseMany(
      'beli nasi 25rb, rokok 30 rb, es 10 rb',
    );

    expect(result, hasLength(3));
    expect(result[0]['amount'], 25000);
    expect(result[0]['category'], 'Makanan');
    expect(result[1]['amount'], 30000);
    expect(result[1]['category'], 'Rokok');
    expect(result[2]['amount'], 10000);
    expect(result[2]['category'], 'Makanan');
  });

  test('mengenali nominal rupiah bertitik dan juta', () {
    expect(TransactionParser.parseOne('beli lipstick Rp50.000')?['amount'], 50000);
    expect(TransactionParser.parseOne('gaji bulan ini 5 juta')?['amount'], 5000000);
    expect(TransactionParser.parseOne('bonus 1,5 juta')?['amount'], 1500000);
  });
}
