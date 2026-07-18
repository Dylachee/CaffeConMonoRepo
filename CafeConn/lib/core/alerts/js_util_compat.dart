/// Drop-in replacement for the removed `dart:js_util`, backed by
/// `dart:js_interop`. Only the handful of functions the alert platform uses.
///
/// Targets dart2js only (this file is reached via the web conditional
/// import), where JS values, dart:html objects and `JSObject` share one
/// runtime representation, so the `as JSObject` casts below are sound.
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

JSAny? _jsArg(Object? value) {
  if (value == null) return null;
  if (value is JSAny) return value;
  return value.jsify();
}

bool hasProperty(Object? o, String name) => (o as JSObject).has(name);

Object? getProperty(Object? o, String name) =>
    (o as JSObject).getProperty(name.toJS);

void setProperty(Object? o, String name, Object? value) =>
    (o as JSObject).setProperty(name.toJS, _jsArg(value));

Object? callMethod(Object? o, String method, List<Object?> args) =>
    (o as JSObject).callMethodVarArgs<JSAny?>(
        method.toJS, args.map(_jsArg).toList());

Object callConstructor(Object? constructor, List<Object?> args) =>
    (constructor as JSFunction)
        .callAsConstructorVarArgs<JSObject>(args.map(_jsArg).toList());

Future<T> promiseToFuture<T>(Object? promise) async {
  final value = await (promise as JSPromise).toDart;
  return value as T;
}

JSAny? jsify(Object? value) => value.jsify();

Object? dartify(Object? value) => (value as JSAny?).dartify();
