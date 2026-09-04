import 'package:flutter/material.dart';

import '../../db_helper.dart';
import '../../mrp/application/mrp_services.dart';
import '../../mrp/domain/mrp_workstation.dart';
import '../application/hrm_job_title_service.dart';
import '../domain/hrm_job_title.dart';

class HrmJobTitlePage extends StatefulWidget {
  const HrmJobTitlePage({super.key});

  @override
  State<HrmJobTitlePage> createState() => _HrmJobTitlePageState();
}

class _HrmJobTitlePageState extends State<HrmJobTitlePage> {
  final _jobTitleService = HrmJobTitleService();
  final _workstationService = MrpWorkstationService();
  late Future<_JobTitlePageData> _data;

  @override
  void initState() {
    super.initState();
    _data = _loadData();
  }

  Future<_JobTitlePageData> _loadData() async {
    final values = await Future.wait([
      _jobTitleService.list(),
      _workstationService.list(),
    ]);
    return _JobTitlePageData(
      titles: values[0] as List<HrmJobTitle>,
      workstations: values[1] as List<MrpWorkstation>,
    );
  }

  Future<void> _edit(_JobTitlePageData data, [HrmJobTitle? current]) async {
    final titleController = TextEditingController(text: current?.title ?? '');
    final descriptionController = TextEditingController(
      text: current?.description ?? '',
    );
    final hoursController = TextEditingController(
      text: current?.contractualHoursPerDay?.toString() ?? '',
    );
    var workstationId = current?.mrpWorkstationId ?? 0;
    final formKey = GlobalKey<FormState>();
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(current == null ? 'Nuevo cargo' : 'Editar cargo'),
        content: SizedBox(
          width: 460,
          child: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: titleController,
                    autofocus: true,
                    decoration: const InputDecoration(labelText: 'Cargo'),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'El cargo es obligatorio'
                        : null,
                  ),
                  TextFormField(
                    controller: descriptionController,
                    decoration: const InputDecoration(labelText: 'Descripción'),
                  ),
                  TextFormField(
                    controller: hoursController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Horas contractuales por día',
                      helperText:
                          'Obligatorio cuando el cargo se vincula a producción',
                    ),
                    validator: (value) {
                      final text = value?.trim() ?? '';
                      if (text.isEmpty) return null;
                      final hours = double.tryParse(text.replaceAll(',', '.'));
                      return hours == null || hours <= 0 || hours > 24
                          ? 'Usa un valor mayor que 0 y hasta 24 horas'
                          : null;
                    },
                  ),
                  DropdownButtonFormField<int>(
                    initialValue: workstationId,
                    decoration: const InputDecoration(
                      labelText: 'Workstation productiva',
                    ),
                    items: [
                      const DropdownMenuItem<int>(
                        value: 0,
                        child: Text('Sin vínculo productivo'),
                      ),
                      ...data.workstations.map(
                        (workstation) => DropdownMenuItem<int>(
                          value: workstation.id,
                          child: Text(workstation.name),
                        ),
                      ),
                    ],
                    onChanged: (value) => workstationId = value ?? 0,
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;
              final hours = double.tryParse(
                hoursController.text.trim().replaceAll(',', '.'),
              );
              final companyId =
                  current?.companyId ??
                  await DatabaseHelper.instance.obtenerEmpresaActivaId();
              final value = HrmJobTitle(
                id: current?.id,
                companyId: companyId,
                title: titleController.text.trim(),
                description: descriptionController.text.trim().isEmpty
                    ? null
                    : descriptionController.text.trim(),
                contractualHoursPerDay: hours,
                mrpWorkstationId: workstationId == 0 ? null : workstationId,
              );
              try {
                if (current == null) {
                  await _jobTitleService.create(value);
                } else {
                  await _jobTitleService.update(value);
                }
                if (dialogContext.mounted) Navigator.pop(dialogContext, true);
              } catch (error) {
                if (!dialogContext.mounted) return;
                ScaffoldMessenger.of(
                  dialogContext,
                ).showSnackBar(SnackBar(content: Text(error.toString())));
              }
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    titleController.dispose();
    descriptionController.dispose();
    hoursController.dispose();
    if (result == true && mounted) setState(() => _data = _loadData());
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<_JobTitlePageData>(
    future: _data,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const Center(child: CircularProgressIndicator());
      }
      if (snapshot.hasError) {
        return Center(
          child: Text('No se pudo cargar cargos: ${snapshot.error}'),
        );
      }
      final data = snapshot.data!;
      return Column(
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: FilledButton.icon(
                onPressed: () => _edit(data),
                icon: const Icon(Icons.add),
                label: const Text('Nuevo cargo'),
              ),
            ),
          ),
          Expanded(
            child: data.titles.isEmpty
                ? const Center(child: Text('No hay cargos configurados.'))
                : ListView.builder(
                    itemCount: data.titles.length,
                    itemBuilder: (context, index) {
                      final title = data.titles[index];
                      final matchingWorkstations = data.workstations
                          .where((item) => item.id == title.mrpWorkstationId)
                          .toList();
                      final workstation = matchingWorkstations.isEmpty
                          ? null
                          : matchingWorkstations.first;
                      return ListTile(
                        title: Text(title.title),
                        subtitle: Text(
                          '${title.contractualHoursPerDay?.toStringAsFixed(2) ?? 'Sin horas'} h/día · '
                          '${workstation?.name ?? 'Sin vínculo productivo'}',
                        ),
                        trailing: IconButton(
                          tooltip: 'Editar cargo',
                          onPressed: () => _edit(data, title),
                          icon: const Icon(Icons.edit_outlined),
                        ),
                      );
                    },
                  ),
          ),
        ],
      );
    },
  );
}

class _JobTitlePageData {
  const _JobTitlePageData({required this.titles, required this.workstations});

  final List<HrmJobTitle> titles;
  final List<MrpWorkstation> workstations;
}
