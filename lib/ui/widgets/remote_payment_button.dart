// lib/ui/widgets/remote_payment_button.dart
//
// Widget reutilizable para iniciar y verificar pagos remotos (Stripe, PayPal,
// Mercado Pago). Expone el flujo correcto:
//
//   1. Crear checkout → se obtiene referencia externa.
//   2. Presentar enlace de aprobación al usuario.
//   3. El usuario aprueba en la plataforma del proveedor.
//   4. "Verificar pago" consulta al proveedor (no HTTP 200 de creación).
//   5. Solo si provider_verified=true se registra el pago en el ERP.
//
// NUNCA se acredita basándose únicamente en el HTTP 200 de creación.

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/currency/money_value.dart';
import '../../integrations/application/payment_checkout_service.dart';
import '../../integrations/application/integration_settings_service.dart';
import '../merka_theme_tokens.dart';

/// Estado del ciclo de vida del pago remoto (visible en la UI).
enum RemotePaymentState {
  idle,       // Sin acción iniciada
  creating,   // Creando checkout con el proveedor
  pending,    // Checkout creado — esperando aprobación del usuario
  verifying,  // Consultando estado con el proveedor
  confirmed,  // Proveedor confirmó el pago (provider_verified = true)
  failed,     // Proveedor rechazó o el pago no pudo verificarse
  expired,    // El checkout expiró sin aprobación
}

/// Resultado completo del proceso de pago remoto.
class RemotePaymentResult {
  const RemotePaymentResult({
    required this.providerVerified,
    required this.provider,
    required this.externalId,
    required this.reference,
    this.rawMetadata = const {},
    this.errorMessage,
  });

  final bool providerVerified;
  final String provider;
  final String externalId;
  final String reference;
  final Map<String, Object?> rawMetadata;
  final String? errorMessage;
}

/// Botón de pago remoto. [onPaymentConfirmed] se llama **solo cuando**
/// el proveedor confirma el pago (provider_verified = true).
class RemotePaymentButton extends StatefulWidget {
  const RemotePaymentButton({
    super.key,
    required this.companyId,
    required this.amount,
    required this.reference,
    required this.onPaymentConfirmed,
    this.description,
    this.returnUrl,
  });

  final int companyId;
  final MoneyValue amount;
  final String reference;
  final String? description;
  final String? returnUrl;

  /// Llamado exclusivamente cuando `provider_verified == true`.
  final void Function(RemotePaymentResult result) onPaymentConfirmed;

  @override
  State<RemotePaymentButton> createState() => _RemotePaymentButtonState();
}

class _RemotePaymentButtonState extends State<RemotePaymentButton> {
  final _svc = PaymentCheckoutService.instance;
  final _settings = IntegrationSettingsService.instance;

  RemotePaymentState _state = RemotePaymentState.idle;
  PaymentCheckoutSession? _session;
  String? _error;

  Future<List<String>> _availableProviders() async {
    final providers = <String>[];
    for (final key in ['stripe', 'paypal', 'mercadopago']) {
      if (await _settings.isConfigured(key)) providers.add(key);
    }
    return providers;
  }

  String _providerLabel(String key) => switch (key) {
        'stripe' => 'Stripe',
        'paypal' => 'PayPal',
        'mercadopago' => 'Mercado Pago',
        _ => key,
      };

  IconData _providerIcon(String key) => switch (key) {
        'stripe' => Icons.credit_card,
        'paypal' => Icons.account_balance_wallet,
        'mercadopago' => Icons.payments,
        _ => Icons.payment,
      };

  @override
  Widget build(BuildContext context) {
    if (_state == RemotePaymentState.confirmed) {
      return _statusChip(
        Icons.check_circle,
        'Pago verificado por el proveedor',
        MerkaThemeTokens.success,
      );
    }
    if (_state == RemotePaymentState.failed) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _statusChip(Icons.error, 'Pago no confirmado', MerkaThemeTokens.danger),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                _error!,
                style: const TextStyle(
                    fontSize: 12, color: MerkaThemeTokens.danger),
              ),
            ),
          const SizedBox(height: 6),
          TextButton(
            onPressed: () => setState(() {
              _state = RemotePaymentState.idle;
              _error = null;
              _session = null;
            }),
            child: const Text('Intentar de nuevo'),
          ),
        ],
      );
    }

    if (_state == RemotePaymentState.pending && _session != null) {
      return _pendingView();
    }

    if (_state == RemotePaymentState.creating ||
        _state == RemotePaymentState.verifying) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 10),
            Text(_state == RemotePaymentState.creating
                ? 'Creando checkout...'
                : 'Verificando con el proveedor...'),
          ],
        ),
      );
    }

    // idle — mostrar selector de proveedor
    return FutureBuilder<List<String>>(
      future: _availableProviders(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const SizedBox.shrink();
        }
        final providers = snapshot.data!;
        if (providers.isEmpty) {
          return const Text(
            'Sin pasarelas configuradas. Ve a Configuración → Integraciones.',
            style: TextStyle(
                fontSize: 12, color: MerkaThemeTokens.graphite600),
          );
        }
        return Wrap(
          spacing: 8,
          children: providers.map((key) {
            return OutlinedButton.icon(
              icon: Icon(_providerIcon(key), size: 16),
              label: Text('Pagar con ${_providerLabel(key)}'),
              onPressed: () => _startCheckout(key),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _pendingView() {
    final session = _session!;
    final hasLink = (session.approvalUrl ?? '').isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _statusChip(
          Icons.hourglass_top,
          'Esperando aprobación — ${_providerLabel(session.provider)}',
          MerkaThemeTokens.warning,
        ),
        const SizedBox(height: 6),
        Text(
          'Referencia: ${session.externalId}',
          style: const TextStyle(fontSize: 12),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            if (hasLink)
              FilledButton.icon(
                icon: const Icon(Icons.open_in_new, size: 16),
                label: const Text('Abrir enlace de pago'),
                onPressed: () async {
                  final url = Uri.parse(session.approvalUrl!);
                  if (await canLaunchUrl(url)) {
                    await launchUrl(url,
                        mode: LaunchMode.externalApplication);
                  }
                },
              ),
            OutlinedButton.icon(
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Verificar pago'),
              onPressed: _verify,
            ),
            TextButton(
              onPressed: () => setState(() {
                _state = RemotePaymentState.idle;
                _session = null;
              }),
              child: const Text('Cancelar'),
            ),
          ],
        ),
        const SizedBox(height: 6),
        const Text(
          'El pago solo se registrará en el sistema cuando el proveedor lo confirme.',
          style: TextStyle(
              fontSize: 11, color: MerkaThemeTokens.graphite600),
        ),
      ],
    );
  }

  Widget _statusChip(IconData icon, String label, Color color) {
    return Chip(
      avatar: Icon(icon, color: color, size: 18),
      label: Text(label, style: TextStyle(color: color, fontSize: 12)),
      backgroundColor: color.withValues(alpha: 0.08),
    );
  }

  // ── Crear checkout ─────────────────────────────────────────────────────────

  Future<void> _startCheckout(String provider) async {
    setState(() {
      _state = RemotePaymentState.creating;
      _error = null;
    });
    try {
      final session = await _createSession(provider);
      if (!mounted) return;
      setState(() {
        _session = session;
        _state = RemotePaymentState.pending;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _state = RemotePaymentState.failed;
        _error = e.toString().replaceFirst('Exception: ', '').replaceFirst('StateError: ', '');
      });
    }
  }

  Future<PaymentCheckoutSession> _createSession(String provider) async {
    return switch (provider) {
      'stripe' => await _svc.createStripeIntent(
          companyId: widget.companyId,
          amount: widget.amount,
          reference: widget.reference,
          description: widget.description,
        ),
      'paypal' => await _svc.createPayPalOrder(
          companyId: widget.companyId,
          amount: widget.amount,
          reference: widget.reference,
          description: widget.description,
          returnUrl: widget.returnUrl,
        ),
      'mercadopago' => await _svc.createMercadoPagoPreference(
          companyId: widget.companyId,
          amount: widget.amount,
          reference: widget.reference,
          title: widget.description ?? 'Pago MerkaERP',
          returnUrl: widget.returnUrl,
        ),
      _ => throw StateError('Proveedor no soportado: $provider'),
    };
  }

  // ── Verificar pago ─────────────────────────────────────────────────────────

  Future<void> _verify() async {
    final session = _session;
    if (session == null) return;
    setState(() => _state = RemotePaymentState.verifying);
    try {
      final result = await _verifySession(session);
      if (!mounted) return;
      final verified = result['provider_verified'] == true;
      setState(() {
        _state = verified
            ? RemotePaymentState.confirmed
            : RemotePaymentState.failed;
        _error = verified
            ? null
            : 'El proveedor indica que el pago aún no ha sido completado o ha sido rechazado.';
      });
      if (verified) {
        widget.onPaymentConfirmed(
          RemotePaymentResult(
            providerVerified: true,
            provider: session.provider,
            externalId: session.externalId,
            reference: widget.reference,
            rawMetadata: result.cast<String, Object?>(),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _state = RemotePaymentState.failed;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<Map<String, Object?>> _verifySession(
      PaymentCheckoutSession session) async {
    return switch (session.provider) {
      'stripe' => await _svc.verifyStripeIntent(
          companyId: widget.companyId,
          paymentIntentId: session.externalId,
          reference: widget.reference,
          expectedAmount: widget.amount,
        ),
      'paypal' => await _svc.verifyPayPalOrder(
          companyId: widget.companyId,
          orderId: session.externalId,
          reference: widget.reference,
          expectedAmount: widget.amount,
        ),
      'mercadopago' => await _svc.verifyMercadoPagoPayment(
          companyId: widget.companyId,
          paymentId: session.externalId,
          reference: widget.reference,
          expectedAmount: widget.amount,
        ),
      _ => throw StateError('Proveedor no soportado: ${session.provider}'),
    };
  }
}
