import 'package:flutter/material.dart';

import '../../../core/currency/public_sector_money.dart';
import '../services/conciliacion_reciprocas_service.dart';

class ConciliacionReciprocaDialog extends StatefulWidget {
  const ConciliacionReciprocaDialog({
    super.key,
    required this.service,
    required this.entidadConsolidadoraId,
    required this.usuarioId,
  });

  final ConciliacionReciprocasService service;
  final String entidadConsolidadoraId;
  final String usuarioId;

  @override
  State<ConciliacionReciprocaDialog> createState() =>
      _ConciliacionReciprocaDialogState();
}

class _ConciliacionReciprocaDialogState
    extends State<ConciliacionReciprocaDialog> {
  final _formKey = GlobalKey<FormState>();
  final _montoAController = TextEditingController();
  final _montoBController = TextEditingController();
  final _toleranciaMontoController = TextEditingController(text: '0');
  final _toleranciaDiasController = TextEditingController(text: '0');
  final _observacionesController = TextEditingController();
  final _vigencia = DateTime.now().year.toString();

  List<Map<String, dynamic>> _partidas = [];
  String? _partidaAId;
  String? _partidaBId;
  String? _error;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _cargarPartidas();
  }

  @override
  void dispose() {
    _montoAController.dispose();
    _montoBController.dispose();
    _toleranciaMontoController.dispose();
    _toleranciaDiasController.dispose();
    _observacionesController.dispose();
    super.dispose();
  }

  Future<void> _cargarPartidas() async {
    try {
      final partidas = await widget.service.listarPartidas(
        entidadConsolidadoraId: widget.entidadConsolidadoraId,
        vigencia: _vigencia,
      );
      if (!mounted) return;
      setState(() {
        _partidas = partidas;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  String _etiqueta(Map<String, dynamic> partida) {
    final debito = publicMoneyFromSql(partida['debito'], nullableAsZero: true);
    final credito = publicMoneyFromSql(
      partida['credito'],
      nullableAsZero: true,
    );
    final valor = debito > publicMoneyZero() ? debito : credito;
    return '${partida['numero_asiento']} | ${partida['entidad_id']} | '
        '${partida['cuenta_codigo']} | ${publicMoneyForDisplay(valor)}';
  }

  String? _validarMonto(String? value) {
    final monto = double.tryParse(value ?? '');
    return monto == null || monto <= 0
        ? 'Ingrese un monto mayor que cero'
        : null;
  }

  Future<void> _aprobar() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.service.aprobarConciliacion(
        entidadConsolidadoraId: widget.entidadConsolidadoraId,
        vigencia: _vigencia,
        usuarioId: widget.usuarioId,
        partidas: [
          PartidaReciprocaInput(
            detalleAsientoId: _partidaAId!,
            montoEliminar: publicMoneyFromMajor(_montoAController.text),
          ),
          PartidaReciprocaInput(
            detalleAsientoId: _partidaBId!,
            montoEliminar: publicMoneyFromMajor(_montoBController.text),
          ),
        ],
        toleranciaMonto: publicMoneyFromMajor(_toleranciaMontoController.text),
        toleranciaDias: int.tryParse(_toleranciaDiasController.text) ?? 0,
        observaciones: _observacionesController.text.trim(),
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Aprobar conciliación recíproca'),
      content: SizedBox(
        width: 620,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _partidas.length < 2
            ? const Text(
                'No hay al menos dos partidas disponibles para conciliar.',
              )
            : SingleChildScrollView(
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _selectorPartida(
                        label: 'Partida 1',
                        value: _partidaAId,
                        onChanged: (value) =>
                            setState(() => _partidaAId = value),
                      ),
                      TextFormField(
                        controller: _montoAController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Monto a eliminar de partida 1',
                        ),
                        validator: _validarMonto,
                      ),
                      _selectorPartida(
                        label: 'Partida 2',
                        value: _partidaBId,
                        onChanged: (value) =>
                            setState(() => _partidaBId = value),
                        segunda: true,
                      ),
                      TextFormField(
                        controller: _montoBController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Monto a eliminar de partida 2',
                        ),
                        validator: _validarMonto,
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _toleranciaMontoController,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: const InputDecoration(
                                labelText: 'Tolerancia de monto',
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: _toleranciaDiasController,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Tolerancia en días',
                              ),
                            ),
                          ),
                        ],
                      ),
                      TextFormField(
                        controller: _observacionesController,
                        decoration: const InputDecoration(
                          labelText: 'Soporte u observaciones',
                        ),
                        maxLines: 2,
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        if (!_loading && _partidas.length >= 2)
          ElevatedButton(
            onPressed: _saving ? null : _aprobar,
            child: const Text('Aprobar'),
          ),
      ],
    );
  }

  Widget _selectorPartida({
    required String label,
    required String? value,
    required ValueChanged<String?> onChanged,
    bool segunda = false,
  }) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: _partidas
          .map(
            (partida) => DropdownMenuItem(
              value: partida['detalle_id'].toString(),
              child: Text(_etiqueta(partida), overflow: TextOverflow.ellipsis),
            ),
          )
          .toList(),
      onChanged: onChanged,
      validator: (selected) => selected == null
          ? 'Requerido'
          : segunda && selected == _partidaAId
          ? 'Seleccione otra partida'
          : null,
    );
  }
}
