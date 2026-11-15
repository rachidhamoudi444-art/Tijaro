/// أي تطبيق هذا؟ يُحدَّد وقت البناء: customer (Tijaro) / driver (Tijaro Driver) / business (Tijaro Business).
const appMode = String.fromEnvironment('APP_MODE', defaultValue: 'customer');

bool get isCustomerApp => appMode == 'customer';
bool get isDriverApp => appMode == 'driver';
bool get isBusinessApp => appMode == 'business';

/// الدور المسموح له بهذا التطبيق.
String get allowedRole => isDriverApp ? 'courier' : (isBusinessApp ? 'store' : 'customer');

String get appModeName => isDriverApp ? 'Tijaro Driver' : (isBusinessApp ? 'Tijaro Business' : 'Tijaro');

/// اسم التطبيق الصحيح لدور معيّن (لتوجيه من دخل بتطبيق خاطئ).
String appNameForRole(String role) {
  switch (role) {
    case 'courier':
      return 'Tijaro Driver';
    case 'store':
      return 'Tijaro Business';
    case 'admin':
      return 'Tijaro Dashboard';
    default:
      return 'Tijaro';
  }
}
