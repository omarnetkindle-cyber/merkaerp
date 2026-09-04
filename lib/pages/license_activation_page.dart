import 'package:flutter/material.dart';
import '../ui/merka_theme_tokens.dart';
import 'package:flutter/services.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../services/hardware_fingerprint_service.dart';
import '../services/licencia_service.dart';
import '../login_page.dart';

class LicenseActivationPage extends StatefulWidget {
  const LicenseActivationPage({super.key, this.onActivated});

  final VoidCallback? onActivated;

  @override
  State<LicenseActivationPage> createState() => _LicenseActivationPageState();
}

class _LicenseActivationPageState extends State<LicenseActivationPage> {
  final HardwareFingerprintService _fingerprintService =
      HardwareFingerprintService();
  final LicenciaService _licenciaService = LicenciaService.instance;

  final _formKey = GlobalKey<FormState>();

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _offlineTokenController = TextEditingController();

  bool _loading = false;
  bool _hasInternet = true;
  // Modo de activación seleccionado manualmente por el usuario.
  // Se preselecciona según conectividad detectada pero el usuario puede cambiarlo.
  bool _useOnlineMode = true;
  String? _hardwareFingerprint;
  String? _uuid;
  String? _errorMessage;
  bool _activationSuccess = false;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    // Generar hardware fingerprint
    _hardwareFingerprint = await _fingerprintService.generateFingerprint();
    _uuid = await _fingerprintService.generateUUID();

    // Verificar conectividad
    final connectivity = await Connectivity().checkConnectivity();
    setState(() {
      _hasInternet = connectivity != ConnectivityResult.none;
      // Preseleccionar modo según conectividad, pero el usuario puede cambiarlo
      _useOnlineMode = connectivity != ConnectivityResult.none;
    });

    // Verificar si ya hay una licencia activa
    final existingLicense = await _licenciaService.obtenerLicencia();
    if (existingLicense != null &&
        existingLicense.estado == EstadoLicencia.activa) {
      setState(() {
        _activationSuccess = true;
      });
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _offlineTokenController.dispose();
    super.dispose();
  }

  Future<void> _activateOnline() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final activated = await _licenciaService.activarDesdeControlCenter(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
        currentHardwareFingerprint: _hardwareFingerprint,
      );

      if (activated) {
        if (!mounted) return;
        setState(() {
          _activationSuccess = true;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Licencia activada exitosamente')),
        );
      } else {
        setState(() {
          _errorMessage =
              'Control Center no devolvió una licencia RS256 válida para este equipo';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error de conexión: $e';
      });
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> _activateOffline() async {
    if (_offlineTokenController.text.trim().isEmpty) {
      setState(() {
        _errorMessage = 'Ingrese el token de activación';
      });
      return;
    }

    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final activated = await _licenciaService.activarDesdeTokenOffline(
        _offlineTokenController.text.trim(),
      );
      if (!mounted) return;
      if (!activated) {
        setState(() {
          _errorMessage = 'Token inválido, expirado o asociado a otro hardware';
        });
        return;
      }

      setState(() {
        _activationSuccess = true;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Licencia activada exitosamente (Offline)'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Error validando token: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  void _copyFingerprint() {
    if (_hardwareFingerprint != null) {
      Clipboard.setData(ClipboardData(text: _hardwareFingerprint!));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Hardware Fingerprint copiado')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_activationSuccess) {
      return _buildSuccessScreen();
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Activación de Licencia')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(),
              const SizedBox(height: 24),
              _buildHardwareInfo(),
              const SizedBox(height: 24),
              _buildConnectionStatus(),
              const SizedBox(height: 16),
              _buildModeSelector(),
              const SizedBox(height: 24),
              if (_useOnlineMode)
                _buildOnlineActivation()
              else
                _buildOfflineActivation(),
              const SizedBox(height: 24),
              if (_errorMessage != null) _buildErrorMessage(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Activar MerkaERP',
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          _useOnlineMode
              ? 'Active su licencia conectándose con el Control Center'
              : 'Modo Offline — Active su licencia con un token de soporte',
          style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
        ),
      ],
    );
  }

  Widget _buildHardwareInfo() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.computer, color: MerkaThemeTokens.info),
                const SizedBox(width: 8),
                Text(
                  'Información del Hardware',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildInfoRow(
              'Hardware Fingerprint',
              _hardwareFingerprint ?? 'Generando...',
            ),
            const SizedBox(height: 8),
            _buildInfoRow('UUID', _uuid ?? 'Generando...'),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _copyFingerprint,
              icon: const Icon(Icons.copy),
              label: const Text('Copiar Fingerprint'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
        ),
        const SizedBox(height: 4),
        SelectableText(
          value,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
        ),
      ],
    );
  }

  Widget _buildModeSelector() {
    return Center(
      child: SegmentedButton<bool>(
        segments: const [
          ButtonSegment<bool>(
            value: true,
            label: Text('Con conexión'),
            icon: Icon(Icons.cloud_outlined),
          ),
          ButtonSegment<bool>(
            value: false,
            label: Text('Sin conexión (token)'),
            icon: Icon(Icons.offline_pin_outlined),
          ),
        ],
        selected: {_useOnlineMode},
        onSelectionChanged: (selection) {
          setState(() {
            _useOnlineMode = selection.first;
            // Limpiar mensaje de error al cambiar modo
            _errorMessage = null;
          });
        },
        style: ButtonStyle(visualDensity: VisualDensity.comfortable),
      ),
    );
  }

  Widget _buildConnectionStatus() {
    return Card(
      color: _hasInternet ? Colors.green.shade50 : Colors.orange.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              _hasInternet ? Icons.wifi : Icons.wifi_off,
              color: _hasInternet ? Colors.green : Colors.orange,
            ),
            const SizedBox(width: 12),
            Text(
              _hasInternet
                  ? 'Conexión a Internet Disponible'
                  : 'Sin Conexión a Internet - Modo Offline',
              style: TextStyle(
                color: _hasInternet
                    ? Colors.green.shade800
                    : Colors.orange.shade800,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOnlineActivation() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.cloud, color: MerkaThemeTokens.info),
                const SizedBox(width: 8),
                const Text(
                  'Activación Online',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _emailController,
              decoration: const InputDecoration(
                labelText: 'Email',
                hintText: 'cliente@empresa.com',
                prefixIcon: Icon(Icons.email),
              ),
              keyboardType: TextInputType.emailAddress,
              validator: (v) => v!.isEmpty ? 'Requerido' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _passwordController,
              decoration: const InputDecoration(
                labelText: 'Contraseña',
                prefixIcon: Icon(Icons.lock),
              ),
              obscureText: true,
              validator: (v) => v!.isEmpty ? 'Requerido' : null,
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _loading ? null : _activateOnline,
                child: _loading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Activar Online'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOfflineActivation() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.offline_pin, color: Colors.orange),
                const SizedBox(width: 8),
                Text(
                  'Activación Offline',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'Ingrese el token de activación proporcionado por el equipo de soporte.',
              style: TextStyle(color: Colors.grey.shade600),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _offlineTokenController,
              decoration: const InputDecoration(
                labelText: 'Token de Activación',
                hintText: 'Pegue el token aquí...',
                prefixIcon: Icon(Icons.key),
              ),
              maxLines: 3,
              validator: (v) => v!.isEmpty ? 'Requerido' : null,
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _loading ? null : _activateOffline,
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                ),
                child: _loading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Activar Offline'),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Para obtener un token, contacte a soporte proporcionando su Hardware Fingerprint.',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorMessage() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Row(
        children: [
          const Icon(Icons.error, color: Colors.red, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _errorMessage!,
              style: const TextStyle(color: Colors.red, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuccessScreen() {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.check_circle, size: 80, color: Colors.green),
                  const SizedBox(height: 24),
                  const Text(
                    'Licencia Activada',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'MerkaERP está listo para usar',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
                  ),
                  const SizedBox(height: 32),
                  FilledButton(
                    onPressed: () {
                      if (widget.onActivated != null) {
                        widget.onActivated!();
                      } else if (Navigator.of(context).canPop()) {
                        Navigator.of(context).pop(true);
                      } else {
                        Navigator.of(context).pushReplacement(
                          MaterialPageRoute(builder: (_) => const LoginPage()),
                        );
                      }
                    },
                    child: const Text('Continuar'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
