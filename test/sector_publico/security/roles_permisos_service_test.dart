/// Pruebas unitarias del camino normativo duro - Fase 0: Seguridad
/// Validaciones marcadas como "✅ Implementada (Dura)"
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:merka_erp/sector_publico/security/roles_permisos_service.dart';

void main() {
  group('Validaciones Normativas Duras - Fase 0', () {
    test('NO debe permitir que tesorero apruebe pagos', () {
      final puedeAprobar = RolesPermisosService.puedeRealizarAccion(
        roles: {RolSectorPublico.tesorero},
        permiso: Permiso.aprobarPago,
      );

      expect(puedeAprobar, isFalse);
    });

    test(
      'NO debe permitir que tesorero se auto-apruebe en segregación de funciones',
      () {
        final cumpleSegregacion =
            RolesPermisosService.validarSegregacionFunciones(
              rolQuienEjecuta: RolSectorPublico.tesorero,
              rolQuienAprobo: RolSectorPublico.tesorero,
              accion: Permiso.aprobarPago,
            );

        expect(cumpleSegregacion, isFalse);
      },
    );

    test('NO debe permitir que contador expida RP según negacionesPorRol', () {
      final tieneNegacion =
          RolesPermisosService.negacionesPorRol[RolSectorPublico.contador]
              ?.contains(Permiso.expedirRP) ??
          false;
      final puedeExpedir = RolesPermisosService.puedeRealizarAccion(
        roles: {RolSectorPublico.contador},
        permiso: Permiso.expedirRP,
      );

      expect(tieneNegacion, isTrue);
      expect(puedeExpedir, isFalse);
    });

    test('Debe permitir que secretario de hacienda apruebe pagos', () {
      final puedeAprobar = RolesPermisosService.puedeRealizarAccion(
        roles: {RolSectorPublico.secretarioHacienda},
        permiso: Permiso.aprobarPago,
      );

      expect(puedeAprobar, isTrue);
    });

    test('Secretario de Hacienda NO puede expedir CDP ni RP', () {
      for (final permiso in {Permiso.expedirCDP, Permiso.expedirRP}) {
        expect(
          RolesPermisosService.tienePermiso(
            RolSectorPublico.secretarioHacienda,
            permiso,
          ),
          isFalse,
        );
        expect(
          RolesPermisosService.puedeRealizarAccion(
            roles: {RolSectorPublico.secretarioHacienda},
            permiso: permiso,
          ),
          isFalse,
        );
      }
    });

    test('Jefe de Presupuesto puede expedir CDP y RP', () {
      for (final permiso in {Permiso.expedirCDP, Permiso.expedirRP}) {
        expect(
          RolesPermisosService.tienePermiso(
            RolSectorPublico.jefePresupuesto,
            permiso,
          ),
          isTrue,
        );
        expect(
          RolesPermisosService.puedeRealizarAccion(
            roles: {RolSectorPublico.jefePresupuesto},
            permiso: permiso,
          ),
          isTrue,
        );
      }
    });

    test('Secretario General administra usuarios sin facultades fiscales', () {
      const rol = RolSectorPublico.secretarioGeneral;

      final permisos = RolesPermisosService.obtenerPermisosEfectivos(rol);
      expect(
        permisos,
        containsAll({Permiso.gestionarUsuarios, Permiso.asignarRoles}),
      );

      for (final permisoFiscal in {
        Permiso.expedirCDP,
        Permiso.expedirRP,
        Permiso.modificarCDP,
        Permiso.modificarRP,
        Permiso.registrarObligacion,
        Permiso.modificarPAC,
        Permiso.aprobarPago,
        Permiso.ejecutarPago,
      }) {
        expect(
          RolesPermisosService.tienePermiso(rol, permisoFiscal),
          isFalse,
          reason: 'Secretario General no puede ${permisoFiscal.name}',
        );
      }
    });

    test('NO debe permitir acción si el rol no tiene permiso', () {
      final puedeAprobar = RolesPermisosService.puedeRealizarAccion(
        roles: {RolSectorPublico.jefePlaneacion},
        permiso: Permiso.aprobarPago,
      );

      expect(puedeAprobar, isFalse);
    });

    test('Solo alcalde y secretario de hacienda pueden configurar entidad', () {
      expect(
        RolesPermisosService.tienePermiso(
          RolSectorPublico.alcaldeRepresentanteLegal,
          Permiso.configurarEntidad,
        ),
        isTrue,
      );
      expect(
        RolesPermisosService.tienePermiso(
          RolSectorPublico.secretarioHacienda,
          Permiso.configurarEntidad,
        ),
        isTrue,
      );
      expect(
        RolesPermisosService.tienePermiso(
          RolSectorPublico.contador,
          Permiso.configurarEntidad,
        ),
        isFalse,
      );
    });
  });
}
