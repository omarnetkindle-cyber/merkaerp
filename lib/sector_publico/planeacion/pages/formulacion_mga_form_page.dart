/// Página de Formulario Formulación MGA
/// Formulario funcional para registro de proyectos MGA
library;

import 'package:flutter/material.dart';
import '../services/formulacion_mga_service.dart';

class FormulacionMGAFormPage extends StatefulWidget {
  final FormulacionMGAService formulacionMGAService;
  final String entidadId;
  final String usuarioId;

  const FormulacionMGAFormPage({
    super.key,
    required this.formulacionMGAService,
    required this.entidadId,
    required this.usuarioId,
  });

  @override
  State<FormulacionMGAFormPage> createState() => _FormulacionMGAFormPageState();
}

class _FormulacionMGAFormPageState extends State<FormulacionMGAFormPage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _codigoBPINController = TextEditingController();
  final TextEditingController _nombreProyectoController = TextEditingController();
  final TextEditingController _problemaCentralController = TextEditingController();
  final TextEditingController _objetivoGeneralController = TextEditingController();
  final TextEditingController _localizacionController = TextEditingController();
  final TextEditingController _poblacionController = TextEditingController();
  final TextEditingController _costoController = TextEditingController();
  final TextEditingController _fuenteController = TextEditingController();
  final TextEditingController _descripcionController = TextEditingController();
  final TextEditingController _justificacionController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _codigoBPINController.dispose();
    _nombreProyectoController.dispose();
    _problemaCentralController.dispose();
    _objetivoGeneralController.dispose();
    _localizacionController.dispose();
    _poblacionController.dispose();
    _costoController.dispose();
    _fuenteController.dispose();
    _descripcionController.dispose();
    _justificacionController.dispose();
    super.dispose();
  }

  Future<void> _registrarProyecto() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    try {
      await widget.formulacionMGAService.registrarProyectoMGA(
        entidadId: widget.entidadId,
        usuarioId: widget.usuarioId,
        codigoBPIN: _codigoBPINController.text,
        nombreProyecto: _nombreProyectoController.text,
        problemaCentral: _problemaCentralController.text,
        objetivoGeneral: _objetivoGeneralController.text,
        localizacionGeografica: _localizacionController.text,
        poblacionBeneficiada: int.parse(_poblacionController.text),
        costoTotal: double.parse(_costoController.text),
        fuenteFinanciacion: _fuenteController.text,
        descripcion: _descripcionController.text.isEmpty ? null : _descripcionController.text,
        justificacion: _justificacionController.text.isEmpty ? null : _justificacionController.text,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Proyecto registrado exitosamente')),
        );
        _limpiarFormulario();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _limpiarFormulario() {
    _codigoBPINController.clear();
    _nombreProyectoController.clear();
    _problemaCentralController.clear();
    _objetivoGeneralController.clear();
    _localizacionController.clear();
    _poblacionController.clear();
    _costoController.clear();
    _fuenteController.clear();
    _descripcionController.clear();
    _justificacionController.clear();
    _formKey.currentState?.reset();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Formulación MGA'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Campos Obligatorios (8)',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _codigoBPINController,
                        decoration: const InputDecoration(
                          labelText: 'Código BPIN (12 dígitos)',
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Ingrese el código BPIN';
                          }
                          if (value.length != 12) {
                            return 'El código BPIN debe tener 12 dígitos';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _nombreProyectoController,
                        decoration: const InputDecoration(
                          labelText: 'Nombre del Proyecto',
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Ingrese el nombre del proyecto';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _problemaCentralController,
                        decoration: const InputDecoration(
                          labelText: 'Problema Central',
                          border: OutlineInputBorder(),
                          hintText: 'Describa el problema que el proyecto busca resolver',
                        ),
                        maxLines: 3,
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Ingrese el problema central';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _objetivoGeneralController,
                        decoration: const InputDecoration(
                          labelText: 'Objetivo General',
                          border: OutlineInputBorder(),
                          hintText: 'Objetivo principal del proyecto',
                        ),
                        maxLines: 3,
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Ingrese el objetivo general';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _localizacionController,
                        decoration: const InputDecoration(
                          labelText: 'Localización Geográfica',
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Ingrese la localización geográfica';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _poblacionController,
                        decoration: const InputDecoration(
                          labelText: 'Población Beneficiada',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Ingrese la población beneficiada';
                          }
                          final poblacion = int.tryParse(value);
                          if (poblacion == null || poblacion <= 0) {
                            return 'La población debe ser mayor a 0';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _costoController,
                        decoration: const InputDecoration(
                          labelText: 'Costo Total del Proyecto',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Ingrese el costo total';
                          }
                          final costo = double.tryParse(value);
                          if (costo == null || costo <= 0) {
                            return 'El costo debe ser mayor a 0';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _fuenteController,
                        decoration: const InputDecoration(
                          labelText: 'Fuente de Financiación',
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Ingrese la fuente de financiación';
                          }
                          return null;
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Información Adicional (Opcional)',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _descripcionController,
                        decoration: const InputDecoration(
                          labelText: 'Descripción Detallada',
                          border: OutlineInputBorder(),
                        ),
                        maxLines: 4,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _justificacionController,
                        decoration: const InputDecoration(
                          labelText: 'Justificación',
                          border: OutlineInputBorder(),
                        ),
                        maxLines: 4,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _isLoading ? null : _registrarProyecto,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: _isLoading
                    ? const CircularProgressIndicator()
                    : const Text('Registrar Proyecto'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
