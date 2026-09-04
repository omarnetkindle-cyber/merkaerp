import '../core/currency/money_value.dart';

/// Retencion laboral mensual basada en la tabla progresiva del articulo 383
/// del Estatuto Tributario.
///
/// La base recibida ya debe contener solo pagos laborales gravables y las
/// deducciones que el sistema tenga soportadas para ese empleado. No usa
/// double ni asume una UVT por defecto.
class PayrollWithholding {
  const PayrollWithholding._();

  static MoneyValue calculate({
    required MoneyValue taxableBase,
    required MoneyValue uvt,
    required MoneyValue zero,
  }) {
    if (uvt.minorUnits <= 0) {
      throw StateError(
        'La UVT de nómina debe estar configurada y ser mayor que cero.',
      );
    }
    final base = taxableBase.minorUnits < 0 ? zero : taxableBase;
    final uvt95 = uvt * 95;
    if (base <= uvt95) return zero;

    final uvt150 = uvt * 150;
    if (base <= uvt150) {
      return (base - uvt95).multiplyDecimal('0.19');
    }

    final uvt360 = uvt * 360;
    if (base <= uvt360) {
      return (base - uvt150).multiplyDecimal('0.28') + (uvt * 10);
    }

    final uvt640 = uvt * 640;
    if (base <= uvt640) {
      return (base - uvt360).multiplyDecimal('0.33') + (uvt * 69);
    }

    final uvt945 = uvt * 945;
    if (base <= uvt945) {
      return (base - uvt640).multiplyDecimal('0.35') + (uvt * 162);
    }

    final uvt2300 = uvt * 2300;
    if (base <= uvt2300) {
      return (base - uvt945).multiplyDecimal('0.37') + (uvt * 268);
    }

    return (base - uvt2300).multiplyDecimal('0.39') + (uvt * 770);
  }
}
