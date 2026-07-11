extension DurationNum on int {
  Duration get ms => Duration(milliseconds: this);
  Duration get seconds => Duration(seconds: this);
  Duration get minutes => Duration(minutes: this);
}

extension Money on double {
  // The café bills in euro; every price/total in the app renders through this
  // single getter. (Name is legacy — kept to avoid churn across ~40 call sites.)
  String get rub => '${toStringAsFixed(2)} €';
}
