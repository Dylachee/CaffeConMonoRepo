import 'package:flutter_test/flutter_test.dart';
import 'package:cafeconnect/screens/shell/main_shell.dart';

void main() {
  test('Smoke test', () {
    expect(true, true);
  });

  test('workspace defaults follow effective capabilities and shift', () {
    expect(
      defaultShellDestination(
        isPlatformOwner: false,
        canManage: false,
        worksOrders: true,
        isOnShift: true,
      ),
      ShellDestination.work,
    );
    expect(
      defaultShellDestination(
        isPlatformOwner: false,
        canManage: true,
        worksOrders: true,
        isOnShift: false,
      ),
      ShellDestination.manage,
    );
    expect(
      defaultShellDestination(
        isPlatformOwner: true,
        canManage: true,
        worksOrders: true,
        isOnShift: true,
      ),
      ShellDestination.manage,
    );
  });
}
