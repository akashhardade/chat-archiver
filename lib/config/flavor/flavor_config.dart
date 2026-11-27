/// Environment types
enum Flavor { dev, prod, stage }

/// App environment configuration (set by `main_dev/stage/prod.dart`).
class FlavorConfig {
  FlavorConfig._();

  static Flavor _flavor = Flavor.dev;

  static void init({String? flavor}) {
    switch (flavor?.toLowerCase()) {
      case 'prod':
        _flavor = Flavor.prod;
      case 'stage':
        _flavor = Flavor.stage;
      default:
        _flavor = Flavor.dev;
    }
  }

  static Flavor get flavor => _flavor;
  static bool get isDevelopment => _flavor == Flavor.dev;
  static bool get isProduction => _flavor == Flavor.prod;
  static bool get isStaging => _flavor == Flavor.stage;
}
