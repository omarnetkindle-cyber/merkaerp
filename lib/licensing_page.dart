import 'dart:io';
import 'package:flutter/material.dart';
import 'ui/merka_theme_tokens.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'control_center_agent.dart';
import 'db_helper.dart';
import 'licensing/domain/license_models.dart';
import 'services/hardware_fingerprint_service.dart';
import 'services/licencia_service.dart';
import 'licensing/domain/product_family.dart';
import 'services/control_center_license_client.dart';
import 'services/control_center_endpoint.dart';

class LicensingPage extends StatefulWidget {
  const LicensingPage({super.key, this.onActivated});

  final VoidCallback? onActivated;

  @override
  State<LicensingPage> createState() => _LicensingPageState();
}

class _LicensingPageState extends State<LicensingPage>
    with SingleTickerProviderStateMixin {
  final _keyController = TextEditingController();
  final _offlineTokenController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  String? _licenseType = 'SUSCRIPCION';

  bool _loading = true;
  String _hardwareId = '';
  String _hardwareFingerprint = '';
  String _currentKey = '';
  String _planName = 'Enterprise Local';
  LicenseStatus _status = LicenseStatus.trial;
  DateTime _expiresAt = DateTime.now().add(const Duration(days: 30));
  static const int _maxCompanies = 5;
  static const int _maxBranches = 20;
  static const int _maxDevices = 50;

  late TabController _tabController;
  final HardwareFingerprintService _fingerprintService =
      HardwareFingerprintService();
  final LicenciaService _licenciaService = LicenciaService.instance;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadLicenseData();
    _loadHardwareFingerprint();
  }

  @override
  void dispose() {
    _keyController.dispose();
    _offlineTokenController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadHardwareFingerprint() async {
    try {
      final fingerprint = await _fingerprintService.generateFingerprint();
      if (mounted) {
        setState(() {
          _hardwareFingerprint = fingerprint;
        });
      }
    } catch (e) {
      debugPrint('Error loading hardware fingerprint: $e');
    }
  }

  Future<void> _loadLicenseData() async {
    setState(() => _loading = true);
    try {
      final db = await DatabaseHelper.instance.database;

      // Hardware ID
      _hardwareId =
          'MERKA-${Platform.localHostname.toUpperCase()}-${Platform.operatingSystem.toUpperCase()}';

      // Fetch stored config
      final keyRows = await db.query(
        'app_config',
        where: 'clave = ?',
        whereArgs: ['license_key'],
        limit: 1,
      );
      if (keyRows.isNotEmpty) {
        _currentKey = keyRows.first['valor']?.toString() ?? '';
      }

      final planRows = await db.query(
        'app_config',
        where: 'clave = ?',
        whereArgs: ['license_plan'],
        limit: 1,
      );
      if (planRows.isNotEmpty) {
        _planName = planRows.first['valor']?.toString() ?? 'Enterprise Local';
      }

      final statusRows = await db.query(
        'app_config',
        where: 'clave = ?',
        whereArgs: ['license_status'],
        limit: 1,
      );
      if (statusRows.isNotEmpty) {
        final st = statusRows.first['valor']?.toString();
        if (st == 'active') _status = LicenseStatus.active;
        if (st == 'expired') _status = LicenseStatus.expired;
        if (st == 'suspended') _status = LicenseStatus.suspended;
      }

      final expireRows = await db.query(
        'app_config',
        where: 'clave = ?',
        whereArgs: ['license_expires_at'],
        limit: 1,
      );
      if (expireRows.isNotEmpty) {
        final dt = DateTime.tryParse(
          expireRows.first['valor']?.toString() ?? '',
        );
        if (dt != null) _expiresAt = dt;
      }

      final licencia = await LicenciaService.instance.obtenerLicencia();
      if (licencia != null) {
        _planName = 'Plan ${licencia.plan.name.toUpperCase()}';
        _status =
            (licencia.estado == EstadoLicencia.activa ||
                licencia.estado == EstadoLicencia.trial)
            ? LicenseStatus.active
            : (licencia.estado == EstadoLicencia.expirada
                  ? LicenseStatus.expired
                  : LicenseStatus.suspended);
        _expiresAt = licencia.fechaExpiracion;
      }
    } catch (e) {
      debugPrint('Error loading license data: $e');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _activateOnline() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Por favor ingrese correo y contraseña válidos.'),
          backgroundColor: MerkaThemeTokens.danger,
        ),
      );
      return;
    }

    setState(() => _loading = true);
    try {
      final db = await DatabaseHelper.instance.database;
      final endpointConfig = await db.query(
        'app_config',
        where: 'clave = ?',
        whereArgs: ['control_center_endpoint'],
        limit: 1,
      );
      final configuredEndpoint = endpointConfig.isNotEmpty
          ? endpointConfig.first['valor']?.toString().trim()
          : null;
      final endpoint = ControlCenterEndpoint.normalize(configuredEndpoint);
      final activated = await _licenciaService.activarDesdeControlCenter(
        email: email,
        password: password,
        client: ControlCenterLicenseClient(endpoint: endpoint),
        fingerprintService: _fingerprintService,
      );

      if (!activated) {
        throw Exception(
          'La licencia recibida no superó la validación firmada.',
        );
      }

      await ControlCenterAgent.reportEvent(
        event: 'license.activated',
        module: 'licensing',
      );

      SystemSound.play(SystemSoundType.click);
      final license = await _licenciaService.obtenerLicencia();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '¡Licencia activada con éxito! Producto: ${license?.productFamily.label ?? 'MerkaERP'}',
            ),
            backgroundColor: MerkaThemeTokens.success,
          ),
        );
      }

      _emailController.clear();
      _passwordController.clear();
      await _loadLicenseData();
      widget.onActivated?.call();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al activar licencia: $e'),
            backgroundColor: MerkaThemeTokens.danger,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _activateOffline() async {
    final token = _offlineTokenController.text.trim();
    if (token.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Por favor ingrese el token de activación.'),
          backgroundColor: MerkaThemeTokens.danger,
        ),
      );
      return;
    }

    setState(() => _loading = true);
    try {
      final success = await _licenciaService.activarDesdeTokenOffline(token);

      if (success) {
        SystemSound.play(SystemSoundType.click);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('¡Licencia activada con éxito!'),
              backgroundColor: MerkaThemeTokens.success,
            ),
          );
        }

        _offlineTokenController.clear();
        await _loadLicenseData();
        widget.onActivated?.call();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Token inválido o expirado.'),
              backgroundColor: MerkaThemeTokens.danger,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al activar licencia: $e'),
            backgroundColor: MerkaThemeTokens.danger,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  int get _daysRemaining {
    final diff = _expiresAt.difference(DateTime.now()).inDays;
    return diff < 0 ? 0 : diff;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: MerkaThemeTokens.info),
        ),
      );
    }

    final isExpired = _daysRemaining == 0 || _status == LicenseStatus.expired;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Gestión de Licencias Empresariales'),
        actions: [
          IconButton(
            tooltip: 'Actualizar estado',
            icon: const Icon(Icons.refresh),
            onPressed: _loadLicenseData,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1000),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header Banner
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: isExpired
                          ? [MerkaThemeTokens.danger, MerkaThemeTokens.danger]
                          : [MerkaThemeTokens.info, MerkaThemeTokens.info],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isExpired
                            ? PhosphorIcons.warningCircle()
                            : PhosphorIcons.shieldCheck(),
                        color: Colors.white,
                        size: 48,
                      ),
                      const SizedBox(width: 20),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Plan Actual: $_planName',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 22,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              isExpired
                                  ? 'Su licencia ha expirado. Por favor active una nueva clave para continuar operando sin restricciones.'
                                  : 'Licencia activa y sincronizada localmente con Merka Control Center.',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white30),
                        ),
                        child: Column(
                          children: [
                            Text(
                              '$_daysRemaining',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 24,
                              ),
                            ),
                            const Text(
                              'Días Restantes',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Details Grid
                LayoutBuilder(
                  builder: (context, constraints) {
                    final compact = constraints.maxWidth < 700;
                    return Wrap(
                      spacing: 16,
                      runSpacing: 16,
                      children: [
                        SizedBox(
                          width: compact
                              ? constraints.maxWidth
                              : (constraints.maxWidth - 16) / 2,
                          child: _InfoCard(
                            title: 'Identificador de Dispositivo (HWID)',
                            value: _hardwareId,
                            icon: PhosphorIcons.desktop(),
                            copyable: true,
                            detail:
                                'Único para esta computadora local. Requerido para licencias offline.',
                          ),
                        ),
                        SizedBox(
                          width: compact
                              ? constraints.maxWidth
                              : (constraints.maxWidth - 16) / 2,
                          child: _InfoCard(
                            title: 'Hardware Fingerprint',
                            value: _hardwareFingerprint.isEmpty
                                ? 'Cargando...'
                                : _hardwareFingerprint,
                            icon: PhosphorIcons.fingerprint(),
                            copyable: true,
                            detail:
                                'Fingerprint para activación offline. Copie y envíe a soporte.',
                          ),
                        ),
                        SizedBox(
                          width: compact
                              ? constraints.maxWidth
                              : (constraints.maxWidth - 16) / 2,
                          child: _InfoCard(
                            title: 'Clave Registrada',
                            value: _currentKey.isEmpty
                                ? 'MKERP-TRIAL-LOCAL-30D'
                                : _currentKey,
                            icon: PhosphorIcons.key(),
                            copyable: true,
                            detail: 'Estado: ${_status.name.toUpperCase()}',
                          ),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 24),

                // Activation Section with Tabs
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            PhosphorIcons.lockKey(),
                            color: MerkaThemeTokens.info,
                            size: 24,
                          ),
                          const SizedBox(width: 12),
                          const Text(
                            'Activar o Renovar Licencia',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: MerkaThemeTokens.graphite900,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      TabBar(
                        controller: _tabController,
                        tabs: const [
                          Tab(text: 'Activación Online'),
                          Tab(text: 'Activación Offline'),
                        ],
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        height: 350,
                        child: TabBarView(
                          controller: _tabController,
                          children: [
                            _buildOnlineActivationTab(),
                            _buildOfflineActivationTab(),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Limits & Features
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Capacidades e Inclusiones del Plan',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const Divider(height: 24),
                      Wrap(
                        spacing: 24,
                        runSpacing: 16,
                        children: [
                          _FeatureMetric(
                            label: 'Empresas Máximas',
                            value: '$_maxCompanies',
                          ),
                          _FeatureMetric(
                            label: 'Sucursales Permitidas',
                            value: '$_maxBranches',
                          ),
                          _FeatureMetric(
                            label: 'Dispositivos POS',
                            value: '$_maxDevices',
                          ),
                          const _FeatureMetric(
                            label: 'Facturación Electrónica DIAN',
                            value: 'Incluido',
                          ),
                          const _FeatureMetric(
                            label: 'Copilot IA Ilimitado',
                            value: 'Incluido',
                          ),
                          const _FeatureMetric(
                            label: 'Sincronización Cloud',
                            value: 'Activa',
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOnlineActivationTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Ingrese su correo y contraseña para activar la licencia en línea.',
          style: TextStyle(fontSize: 13, color: MerkaThemeTokens.graphite600),
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _emailController,
          decoration: const InputDecoration(
            hintText: 'Correo electrónico',
            prefixIcon: Icon(Icons.email_outlined),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(12)),
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _passwordController,
          obscureText: true,
          decoration: const InputDecoration(
            hintText: 'Contraseña',
            prefixIcon: Icon(Icons.lock_outlined),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(12)),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            const Text('Tipo de licencia: '),
            DropdownButton<String>(
              value: _licenseType,
              items: const [
                DropdownMenuItem(
                  value: 'SUSCRIPCION',
                  child: Text('Suscripción'),
                ),
                DropdownMenuItem(value: 'PERPETUA', child: Text('Perpetua')),
              ],
              onChanged: (value) {
                setState(() => _licenseType = value);
              },
            ),
          ],
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: FilledButton.icon(
            onPressed: _activateOnline,
            icon: const Icon(Icons.check_circle_outline),
            label: const Text(
              'ACTIVAR EN LÍNEA',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: MerkaThemeTokens.info,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildOfflineActivationTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Ingrese el token de activación offline proporcionado por el equipo de soporte.',
          style: TextStyle(fontSize: 13, color: MerkaThemeTokens.graphite600),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _offlineTokenController,
                maxLines: 3,
                decoration: const InputDecoration(
                  hintText: 'Pegue el token aquí...',
                  prefixIcon: Icon(Icons.key),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(12)),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),
            SizedBox(
              height: 48,
              child: FilledButton.icon(
                onPressed: _activateOffline,
                icon: const Icon(Icons.offline_pin),
                label: const Text(
                  'ACTIVAR OFFLINE',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: MerkaThemeTokens.success,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.title,
    required this.value,
    required this.icon,
    this.copyable = false,
    required this.detail,
  });

  final String title;
  final String value;
  final IconData icon;
  final bool copyable;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: MerkaThemeTokens.graphite600),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: MerkaThemeTokens.graphite600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  value,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace',
                    color: MerkaThemeTokens.graphite900,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (copyable)
                IconButton(
                  tooltip: 'Copiar al portapapeles',
                  icon: const Icon(
                    Icons.copy,
                    size: 16,
                    color: MerkaThemeTokens.info,
                  ),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: value));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Copiado al portapapeles'),
                        duration: Duration(seconds: 1),
                      ),
                    );
                  },
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            detail,
            style: const TextStyle(
              fontSize: 11,
              color: MerkaThemeTokens.graphite600,
            ),
          ),
        ],
      ),
    );
  }
}

class _FeatureMetric extends StatelessWidget {
  const _FeatureMetric({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 180,
      child: Row(
        children: [
          const Icon(
            Icons.check_circle,
            size: 16,
            color: MerkaThemeTokens.success,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: MerkaThemeTokens.graphite900,
                  ),
                ),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 10,
                    color: MerkaThemeTokens.graphite600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
