/// Página de Onboarding para Selección de Tipo de Entidad
/// Formulario funcional conectado al servicio SelectorEntidadService
library;

import 'package:flutter/material.dart';
import '../services/selector_entidad_service.dart';

class OnboardingEntidadPage extends StatefulWidget {
  final SelectorEntidadService selectorEntidadService;
  final String entidadId;
  final String usuarioId;

  const OnboardingEntidadPage({
    super.key,
    required this.selectorEntidadService,
    required this.entidadId,
    required this.usuarioId,
  });

  @override
  State<OnboardingEntidadPage> createState() => _OnboardingEntidadPageState();
}

class _OnboardingEntidadPageState extends State<OnboardingEntidadPage> {
  final _formKey = GlobalKey<FormState>();
  TipoEntidad? _tipoEntidad;
  String? _subtipo;
  final TextEditingController _nombreEntidadController = TextEditingController();
  final TextEditingController _codigoDANEController = TextEditingController();
  final TextEditingController _departamentoController = TextEditingController();
  final TextEditingController _municipioController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _nombreEntidadController.dispose();
    _codigoDANEController.dispose();
    _departamentoController.dispose();
    _municipioController.dispose();
    super.dispose();
  }

  Future<void> _guardarConfiguracion() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await widget.selectorEntidadService.configurarTipoEntidad(
        entidadId: widget.entidadId,
        usuarioId: widget.usuarioId,
        tipo: _tipoEntidad!,
        subtipo: _subtipo,
        nombreEntidad: _nombreEntidadController.text,
        codigoDANE: _codigoDANEController.text,
        departamento: _departamentoController.text,
        municipio: _municipioController.text.isEmpty ? null : _municipioController.text,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Configuración guardada exitosamente')),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Configuración de Entidad'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_errorMessage != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16.0),
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Tipo de Entidad',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<TipoEntidad>(
                        initialValue: _tipoEntidad,
                        decoration: const InputDecoration(
                          labelText: 'Tipo de Entidad',
                          border: OutlineInputBorder(),
                        ),
                        items: TipoEntidad.values.map((tipo) {
                          return DropdownMenuItem(
                            value: tipo,
                            child: Text(_obtenerNombreTipo(tipo)),
                          );
                        }).toList(),
                        onChanged: (value) {
                          setState(() {
                            _tipoEntidad = value;
                            _subtipo = null;
                          });
                        },
                        validator: (value) {
                          if (value == null) {
                            return 'Seleccione el tipo de entidad';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      if (_tipoEntidad == TipoEntidad.municipio ||
                          _tipoEntidad == TipoEntidad.distrito)
                        DropdownButtonFormField<String>(
                          initialValue: _subtipo,
                          decoration: const InputDecoration(
                            labelText: 'Subtipo',
                            border: OutlineInputBorder(),
                          ),
                          items: widget.selectorEntidadService
                              .obtenerSubtiposValidos(_tipoEntidad!)
                              .map((subtipo) {
                            return DropdownMenuItem(
                              value: subtipo,
                              child: Text(_obtenerNombreSubtipo(subtipo)),
                            );
                          }).toList(),
                          onChanged: (value) {
                            setState(() {
                              _subtipo = value;
                            });
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
                        'Información de la Entidad',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _nombreEntidadController,
                        decoration: const InputDecoration(
                          labelText: 'Nombre de la Entidad',
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Ingrese el nombre de la entidad';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _codigoDANEController,
                        decoration: const InputDecoration(
                          labelText: 'Código DANE',
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Ingrese el código DANE';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _departamentoController,
                        decoration: const InputDecoration(
                          labelText: 'Departamento',
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Ingrese el departamento';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _municipioController,
                        decoration: const InputDecoration(
                          labelText: 'Municipio (opcional)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _isLoading ? null : _guardarConfiguracion,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: _isLoading
                    ? const CircularProgressIndicator()
                    : const Text('Guardar Configuración'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _obtenerNombreTipo(TipoEntidad tipo) {
    switch (tipo) {
      case TipoEntidad.departamento:
        return 'Departamento';
      case TipoEntidad.municipio:
        return 'Municipio';
      case TipoEntidad.distrito:
        return 'Distrito';
      case TipoEntidad.hospitalEse:
        return 'Hospital ESE';
      case TipoEntidad.otroEnte:
        return 'Otro ente';
      case TipoEntidad.regionMetropolitana:
        return 'Región Metropolitana';
    }
  }

  String _obtenerNombreSubtipo(String subtipo) {
    return subtipo.replaceAll('_', ' ').split(' ').map((palabra) {
      return palabra[0].toUpperCase() + palabra.substring(1);
    }).join(' ');
  }
}
