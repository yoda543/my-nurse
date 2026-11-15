import 'package:intl/intl.dart';

final _money = NumberFormat.decimalPattern('fr_FR');
final _date = DateFormat("EEE d MMM 'à' HH'h'mm", 'fr_FR');
final _time = DateFormat("HH'h'mm", 'fr_FR');

String fcfa(int amount) => '${_money.format(amount)} FCFA';
String dateTimeLabel(DateTime d) => _date.format(d);
String timeLabel(DateTime d) => _time.format(d);
