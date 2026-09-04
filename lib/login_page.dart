import 'package:flutter/material.dart';

import 'app_session.dart';
import 'db_helper.dart';
import 'logo_widget.dart';
import 'main.dart';
import 'services/sync_service.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final usuarioCtrl = TextEditingController(text: 'admin');
  final pinCtrl = TextEditingController();
  bool cargando = false;

  @override
  void dispose() {
    usuarioCtrl.dispose();
    pinCtrl.dispose();
    super.dispose();
  }

  Future<String?> _solicitarPinInicial() async {
    final pinNuevoCtrl = TextEditingController();
    final confirmacionCtrl = TextEditingController();
    String? error;
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Protege la cuenta administradora'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Esta instalación todavía no tiene un PIN local. Define uno antes de continuar.',
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: pinNuevoCtrl,
                  obscureText: true,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Nuevo PIN',
                    helperText: 'Mínimo 6 caracteres',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: confirmacionCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Confirmar PIN'),
                ),
                if (error != null) ...[
                  const SizedBox(height: 10),
                  Text(error!, style: const TextStyle(color: Colors.red)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () {
                final pin = pinNuevoCtrl.text.trim();
                final confirmacion = confirmacionCtrl.text.trim();
                if (pin.length < 6) {
                  setDialogState(
                    () => error = 'El PIN debe tener al menos 6 caracteres.',
                  );
                  return;
                }
                if (pin != confirmacion) {
                  setDialogState(() => error = 'Los PIN no coinciden.');
                  return;
                }
                Navigator.pop(dialogContext, pin);
              },
              child: const Text('Guardar PIN'),
            ),
          ],
        ),
      ),
    );
    pinNuevoCtrl.dispose();
    confirmacionCtrl.dispose();
    return result;
  }

  Future<void> _entrar() async {
    setState(() => cargando = true);

    try {
      final requierePin = await DatabaseHelper.instance
          .usuarioRequierePinInicial(usuarioCtrl.text);
      if (requierePin) {
        if (!mounted) return;
        setState(() => cargando = false);
        final nuevoPin = await _solicitarPinInicial();
        if (nuevoPin == null) return;
        final configurado = await DatabaseHelper.instance.configurarPinInicial(
          usuario: usuarioCtrl.text,
          pin: nuevoPin,
        );
        if (!configurado) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No fue posible configurar el PIN inicial.'),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }
        pinCtrl.text = nuevoPin;
        if (mounted) setState(() => cargando = true);
      }

      final usuario = await DatabaseHelper.instance.validarUsuarioLocal(
        usuario: usuarioCtrl.text,
        pin: pinCtrl.text,
      );

      if (!mounted) return;
      setState(() => cargando = false);

      if (usuario == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Usuario o PIN incorrecto.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      AppSession.iniciar(usuario);
      await AppSession.resolverEntidadActiva();

      // La sincronización usa la licencia firmada de la instalación. El usuario
      // y el PIN locales nunca deben enviarse al Control Center.
      try {
        await SyncService.instance.refreshLicenseSession();
      } catch (_) {}

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const MenuPrincipal()),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => cargando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al iniciar sesión: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 820;
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 980),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: wide
                      ? Row(
                          children: [
                            const Expanded(child: _BrandPanel()),
                            const SizedBox(width: 18),
                            Expanded(
                              child: _LoginPanel(
                                usuarioCtrl: usuarioCtrl,
                                pinCtrl: pinCtrl,
                                cargando: cargando,
                                onSubmit: _entrar,
                              ),
                            ),
                          ],
                        )
                      : ListView(
                          shrinkWrap: true,
                          children: [
                            const _BrandPanel(compact: true),
                            const SizedBox(height: 14),
                            _LoginPanel(
                              usuarioCtrl: usuarioCtrl,
                              pinCtrl: pinCtrl,
                              cargando: cargando,
                              onSubmit: _entrar,
                            ),
                          ],
                        ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _BrandPanel extends StatelessWidget {
  const _BrandPanel({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(compact ? 18 : 24),
      decoration: BoxDecoration(
        color: AppBrand.primary,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const MerkaLogo(size: 64),
          SizedBox(height: compact ? 14 : 22),
          Text(
            AppBrand.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            AppBrand.description,
            maxLines: compact ? 2 : 3,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: Colors.white.withValues(alpha: 0.88),
              fontWeight: FontWeight.w600,
            ),
          ),
          if (!compact) ...[
            const SizedBox(height: 24),
            const _BrandBullet(
              icon: Icons.account_tree,
              text: 'Arquitectura modular para operacion, finanzas y control.',
            ),
            const _BrandBullet(
              icon: Icons.domain,
              text: 'Multiempresa con datos aislados por organizacion.',
            ),
            const _BrandBullet(
              icon: Icons.verified,
              text:
                  'Contabilidad, permisos y trazabilidad preparados para crecer.',
            ),
          ],
        ],
      ),
    );
  }
}

class _BrandBullet extends StatelessWidget {
  const _BrandBullet({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, color: AppBrand.accent, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

class _LoginPanel extends StatelessWidget {
  const _LoginPanel({
    required this.usuarioCtrl,
    required this.pinCtrl,
    required this.cargando,
    required this.onSubmit,
  });

  final TextEditingController usuarioCtrl;
  final TextEditingController pinCtrl;
  final bool cargando;
  final Future<void> Function() onSubmit;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const MerkaBrandHeader(compact: true),
          const SizedBox(height: 24),
          Text(
            'Ingreso seguro',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w900,
              color: AppBrand.ink,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Accede al entorno ERP de la empresa activa.',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: AppBrand.muted),
          ),
          const SizedBox(height: 18),
          TextField(
            controller: usuarioCtrl,
            decoration: const InputDecoration(
              labelText: 'Usuario',
              prefixIcon: Icon(Icons.person),
            ),
            onSubmitted: (_) => onSubmit(),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: pinCtrl,
            obscureText: true,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'PIN',
              prefixIcon: Icon(Icons.lock),
            ),
            onSubmitted: (_) => onSubmit(),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: cargando ? null : onSubmit,
            icon: cargando
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.login),
            label: const Text('Iniciar sesión'),
          ),
          const SizedBox(height: 10),
          Text(
            'Usa el usuario y PIN definidos durante la configuración inicial.',
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: AppBrand.muted),
          ),
        ],
      ),
    );
  }
}
