import 'package:flutter/material.dart';

import 'licensing/domain/product_family.dart';
import 'logo_widget.dart';
import 'services/licencia_service.dart';

class ManualPage extends StatelessWidget {
  const ManualPage({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: LicenciaService.instance.obtenerLicencia(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        final family = snapshot.data?.productFamily ?? ProductFamily.commercial;
        final publicSector = family == ProductFamily.publicSector;
        final sections = publicSector ? _publicSections : _commercialSections;
        return Scaffold(
          appBar: AppBar(title: Text(publicSector ? 'Manual · MerkaERP Público' : 'Manual · MerkaERP Comercial')),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  border: Border.all(color: Theme.of(context).colorScheme.outline),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const MerkaBrandHeader(),
                    const SizedBox(height: 14),
                    Text(
                      publicSector ? 'Manual operativo · Sector Público' : 'Manual operativo · Comercial',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      publicSector
                          ? 'La licencia Pública muestra únicamente procesos institucionales. No existe un selector para cambiar al producto Comercial.'
                          : 'La licencia Comercial muestra únicamente procesos empresariales. No existe un selector para cambiar al producto Público.',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              _ManualSectionCard(section: publicSector ? _publicStartup : _commercialStartup),
              const SizedBox(height: 10),
              ...sections.map(
                (section) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _ManualSectionCard(section: section),
                ),
              ),
              const _ManualSectionCard(section: _commonGovernance),
            ],
          ),
        );
      },
    );
  }
}

class _ManualSection {
  const _ManualSection({
    required this.title,
    required this.icon,
    required this.summary,
    required this.items,
  });

  final String title;
  final IconData icon;
  final String summary;
  final List<String> items;
}

class _ManualSectionCard extends StatelessWidget {
  const _ManualSectionCard({required this.section});

  final _ManualSection section;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Theme.of(context).colorScheme.outline),
      ),
      child: ExpansionTile(
        leading: Icon(section.icon, color: Theme.of(context).colorScheme.secondary),
        title: Text(section.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(section.summary, style: Theme.of(context).textTheme.bodySmall),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Divider(),
                ...section.items.map(
                  (item) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('• ', style: TextStyle(color: Theme.of(context).colorScheme.secondary, fontWeight: FontWeight.bold)),
                        Expanded(child: Text(item, style: const TextStyle(fontSize: 13, height: 1.3))),
                      ],
                    ),
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

const _commercialStartup = _ManualSection(
  title: 'Inicio y puesta en marcha',
  icon: Icons.rocket_launch,
  summary: 'Configura la empresa sin mezclarla con funciones del Sector Público.',
  items: [
    'El onboarding solicita identidad empresarial, operación, configuración fiscal, continuidad y usuarios iniciales.',
    'La familia Comercial proviene de la licencia firmada y no puede cambiarse desde preferencias ni desde la base local.',
    'Antes de operar configura moneda, impuestos, cuentas, bodegas, caja, responsables y política de respaldo.',
    'Si vienes de otro software, el onboarding puede abrir el asistente de migración inmediatamente o dejarlo disponible para después.',
  ],
);

const _publicStartup = _ManualSection(
  title: 'Inicio y puesta en marcha',
  icon: Icons.account_balance,
  summary: 'Configura la entidad y sus instrumentos sin exponer módulos comerciales.',
  items: [
    'El onboarding solicita identidad de la entidad, tipo institucional, estructura, continuidad y responsables.',
    'La familia Pública proviene de la licencia firmada y no puede convertirse en Comercial desde la aplicación.',
    'Parametriza dependencias, vigencia, estructura presupuestal, contabilidad pública, responsables e instrumentos archivísticos aplicables.',
    'PGD, TRD/TVD, políticas, términos y demás decisiones institucionales se configuran con los actos y parámetros propios de cada entidad.',
  ],
);

const List<_ManualSection> _commercialSections = [
  _ManualSection(
    title: 'POS, ventas y caja',
    icon: Icons.point_of_sale,
    summary: 'Opera ventas de contado, crédito y pago mixto con inventario y contabilidad integrados.',
    items: [
      'El POS valida existencias, impuestos, cliente y medios de pago antes de finalizar.',
      'Ventas de contado afectan caja/banco; ventas a crédito generan cartera; pagos mixtos separan cada componente.',
      'La anulación respeta caja, banco, cartera, Kardex y asiento contable del documento original.',
      'Apertura, movimientos, arqueo y cierre de caja quedan trazados por usuario y no deben borrarse para corregir diferencias.',
    ],
  ),
  _ManualSection(
    title: 'Compras, proveedores e inventario',
    icon: Icons.inventory_2,
    summary: 'Abastecimiento, lotes, vencimientos, bodegas y costo integrados.',
    items: [
      'Las compras pueden crear inventario, Kardex, cuentas por pagar y asientos en una misma operación transaccional.',
      'Usa lotes, vencimientos, series/variantes y bodegas cuando aplique a la operación de la empresa.',
      'Revisa stock mínimo, productos sin movimiento, rotación y sugerencias de reposición antes de emitir nuevas compras.',
      'Los ajustes manuales requieren permisos y quedan en auditoría.',
    ],
  ),
  _ManualSection(
    title: 'Cartera, tesorería y contabilidad',
    icon: Icons.account_balance_wallet_outlined,
    summary: 'Controla cobros, pagos, bancos, periodos y estados financieros.',
    items: [
      'Cuentas por cobrar/pagar conservan saldos y abonos vinculados con su origen.',
      'La contabilidad utiliza dinero en unidades menores enteras para evitar errores binarios de redondeo.',
      'Revisa balance de comprobación, auxiliares, estados financieros, conciliaciones y periodos antes de cierres.',
      'No elimines movimientos contables para corregirlos: usa reversos o documentos de ajuste con trazabilidad.',
    ],
  ),
  _ManualSection(
    title: 'CRM, HRM y MRP',
    icon: Icons.hub_outlined,
    summary: 'Gestión comercial, talento humano y planeación de requerimientos sobre un núcleo común.',
    items: [
      'CRM administra oportunidades, actividades y relación con clientes sin sustituir la venta contabilizada.',
      'HRM centraliza personal y novedades; las integraciones de nómina deben respetar aprobaciones y periodos.',
      'MRP usa demanda, productos e inventario para planeación; verifica parámetros antes de convertir sugerencias en operaciones reales.',
    ],
  ),
  _ManualSection(
    title: 'Gestión documental empresarial',
    icon: Icons.folder_copy_outlined,
    summary: 'Radicados, expedientes, documentos, versiones, préstamos y archivo empresarial.',
    items: [
      'Puedes radicar comunicaciones recibidas, enviadas e internas y seguir cada actuación.',
      'Los expedientes relacionan documentos, versiones y entidades del ERP sin depender de carpetas sueltas de Windows.',
      'Los archivos almacenados conservan SHA-256 y controles de acceso; los originales no deben reemplazarse fuera de MerkaERP.',
      'La capa archivística institucional TRD/TVD/PGD es exclusiva de MerkaERP Público.',
    ],
  ),
  _ManualSection(
    title: 'Facturación electrónica e integraciones',
    icon: Icons.integration_instructions_outlined,
    summary: 'Credenciales por empresa y confirmación real de proveedores externos.',
    items: [
      'DIAN/PTA, WhatsApp, correo, pagos, nube y otras integraciones se configuran con las credenciales del cliente.',
      'Una integración no configurada falla de forma explícita; MerkaERP no simula transmisiones o recaudos.',
      'Crear un checkout remoto no significa pago recibido: Stripe, PayPal y Mercado Pago deben confirmar referencia, importe, moneda y estado.',
      'Las credenciales sensibles se mantienen fuera de la base operativa cuando la plataforma permite almacenamiento seguro.',
    ],
  ),
  _ManualSection(
    title: 'Migración desde otro sistema',
    icon: Icons.move_down_outlined,
    summary: 'Trae maestros y saldos vigentes conservando el histórico original.',
    items: [
      'Admite CSV/TSV/TXT, Excel, JSON y SQLite; primero revisa la vista previa y el mapeo de columnas.',
      'Clientes, proveedores, productos, inventario, cartera y saldos contables pueden convertirse en datos operativos cuando existe equivalencia segura.',
      'Las hojas sin equivalencia pueden conservarse completas en Archivo Legado sin forzar transformaciones.',
      'Las carpetas de documentos anteriores pueden incorporarse al SGDEA en un expediente restringido, con ruta relativa y SHA-256.',
      'Toda migración crea respaldo previo, traza origen→destino, conciliación y rollback controlado.',
    ],
  ),
];

const List<_ManualSection> _publicSections = [
  _ManualSection(
    title: 'Planeación y presupuesto público',
    icon: Icons.account_tree_outlined,
    summary: 'Estructura presupuestal, fuentes, apropiaciones y ejecución trazable.',
    items: [
      'Configura vigencias, rubros, fuentes y estructura de la entidad antes de iniciar ejecución.',
      'La cadena presupuestal debe mantener Apropiación → CDP → RP → Obligación → Pago con saldos consistentes.',
      'Modificaciones, reservas, cuentas por pagar y vigencias deben documentarse según la política y actos de la entidad.',
      'Los tableros permiten comparar apropiación, compromisos, obligaciones, pagos y saldos por fuente/rubro.',
    ],
  ),
  _ManualSection(
    title: 'Contratación y supervisión',
    icon: Icons.assignment_turned_in_outlined,
    summary: 'Expediente contractual, ejecución física/financiera, garantías y pagos.',
    items: [
      'Relaciona cada proceso/contrato con CDP, RP, tercero, objeto, plazo, garantías y expediente documental.',
      'El supervisor registra actuaciones, informes, avances, novedades y soportes antes de autorizar pagos.',
      'Los vencimientos de contrato y garantías deben gestionarse desde alertas y no desde recordatorios externos aislados.',
      'SECOP u otros portales solo se marcan como transmitidos cuando la integración configurada confirma el resultado.',
    ],
  ),
  _ManualSection(
    title: 'Tesorería y contabilidad pública',
    icon: Icons.account_balance_wallet_outlined,
    summary: 'Obligaciones, pagos, conciliación y contabilidad pública conectadas con presupuesto.',
    items: [
      'La obligación y el pago conservan vínculo con su origen presupuestal y documental.',
      'El catálogo contable público usa naturaleza y clasificación compatibles con el modelo institucional configurado.',
      'Los asientos deben mantener partida doble; las correcciones se trazan mediante reversos/ajustes, no borrado de historia.',
      'Conciliaciones y reportes de control deben contrastarse con saldos presupuestales y bancarios antes del cierre.',
    ],
  ),
  _ManualSection(
    title: 'SGDEA y gestión documental',
    icon: Icons.folder_shared_outlined,
    summary: 'Radicación, trámite, expedientes, archivo, instrumentos y ciclo vital documental.',
    items: [
      'Radica comunicaciones recibidas, enviadas e internas con consecutivo, fecha, remitente/destinatario y seguimiento.',
      'Cada expediente reúne radicados, documentos, versiones, firmas/evidencias, accesos y actuaciones.',
      'TRD/TVD, PGD y demás instrumentos se parametrizan con la información aprobada por la entidad; el software no inventa periodos de retención.',
      'Transferencias, ubicación física, préstamos, FUID, disposición y bitácora mantienen trazabilidad del ciclo documental.',
      'Documentos reservados, clasificados o con datos personales requieren permisos en la interfaz y en la capa de servicio.',
    ],
  ),
  _ManualSection(
    title: 'Bienes, almacén, proyectos y control',
    icon: Icons.domain_outlined,
    summary: 'Activos, inventarios, programas/proyectos, riesgos y seguimiento institucional.',
    items: [
      'Bienes y almacén deben mantener responsable, ubicación, movimientos y soporte documental.',
      'Planes, programas, proyectos, metas e indicadores permiten relacionar avance físico y financiero.',
      'Control interno puede registrar riesgos, hallazgos, acciones y planes de mejoramiento con evidencia.',
      'Los reportes a organismos externos se preparan localmente y solo cambian a enviados cuando existe confirmación real del canal configurado.',
    ],
  ),
  _ManualSection(
    title: 'Interoperabilidad institucional',
    icon: Icons.cloud_sync_outlined,
    summary: 'SECOP, CHIP/CGN, SIIF, PILA, BPIN, transparencia y otros servicios configurados por la entidad.',
    items: [
      'Cada entidad introduce sus endpoints/credenciales autorizados desde el Centro de Integraciones.',
      'Exportar un archivo no equivale a transmitirlo; la operación externa debe tener respuesta verificable.',
      'HTTP externo no se acepta para integraciones sensibles; localhost puede usarse únicamente en desarrollo controlado.',
      'Las integraciones no utilizadas permanecen deshabilitadas y no bloquean la operación local que no dependa de ellas.',
    ],
  ),
  _ManualSection(
    title: 'Migración institucional',
    icon: Icons.move_to_inbox_outlined,
    summary: 'Arranque a mitad de vigencia sin reconstruir de forma ficticia documentos históricos.',
    items: [
      'Importa terceros, catálogo contable, apropiación vigente, ejecución acumulada y apertura contable cuando los datos cumplen validaciones.',
      'La jerarquía Pagado ≤ Obligado ≤ RP ≤ CDP ≤ Apropiación se valida antes de aceptar saldos presupuestales de apertura.',
      'Los CDP/RP/obligaciones/pagos históricos que no puedan reconstruirse con evidencia permanecen en Archivo Legado/SGDEA, no se inventan como operaciones nativas.',
      'Carpetas y expedientes digitales heredados pueden preservarse con hashes y acceso restringido inicial.',
      'La conciliación posterior identifica registros faltantes o modificados después de la migración.',
    ],
  ),
];

const _commonGovernance = _ManualSection(
  title: 'Continuidad, soporte y Go-Live',
  icon: Icons.health_and_safety_outlined,
  summary: 'Reglas mínimas antes de depender del ERP en operación diaria.',
  items: [
    'Crea y verifica respaldos integrales periódicos; incluyen base de datos y repositorio documental.',
    'Ejecuta un simulacro de restauración antes de la puesta en marcha y después de cambios de infraestructura importantes.',
    'Usa Salud y Soporte para revisar integridad y exportar un paquete técnico sin credenciales ni contenido documental.',
    'Completa el checklist Go-Live/UAT. Los controles automáticos de release, analyzer y tests no pueden aprobarse manualmente.',
    'Exporta la evidencia Go-Live con su checksum SHA-256 y consérvala con la documentación de puesta en marcha.',
    'Antes de actualizar, deja que MerkaERP cree el respaldo previo y valida que la versión corresponda a la familia licenciada.',
  ],
);
