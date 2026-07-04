extension DurationNum on int {
  Duration get ms => Duration(milliseconds: this);
  Duration get seconds => Duration(seconds: this);
  Duration get minutes => Duration(minutes: this);
}

extension Money on double {
  String get rub => '${toStringAsFixed(2)} \$';
}
