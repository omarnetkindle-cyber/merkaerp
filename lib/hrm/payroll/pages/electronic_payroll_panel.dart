import 'package:flutter/material.dart';
import '../application/electronic_payroll_service.dart';

class ElectronicPayrollPanel extends StatefulWidget {
  const ElectronicPayrollPanel({super.key});
  @override
  State<ElectronicPayrollPanel> createState() => _ElectronicPayrollPanelState();
}
class _ElectronicPayrollPanelState extends State<ElectronicPayrollPanel> {
  late Future<List<Map<String,dynamic>>> _future;
  @override void initState(){super.initState();_future=ElectronicPayrollService.instance.listDocuments();}
  void _reload()=>setState(()=>_future=ElectronicPayrollService.instance.listDocuments());
  Future<void> _run(Future<void> Function() action) async { try { await action(); _reload(); } catch(e){ if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.toString()))); } }
  @override Widget build(BuildContext context)=>FutureBuilder<List<Map<String,dynamic>>>(future:_future,builder:(context,s){
    if(s.connectionState!=ConnectionState.done)return const Center(child:CircularProgressIndicator());
    if(s.hasError)return Center(child:Text('No fue posible cargar nómina electrónica: ${s.error}'));
    final rows=s.data!;
    return ListView(padding:const EdgeInsets.all(16),children:[
      Card(child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text('Nómina electrónica',style:Theme.of(context).textTheme.titleLarge),const SizedBox(height:6),
        const Text('Usa las liquidaciones ya generadas en HRM. Configura el proveedor tecnológico en Integraciones; enviar no equivale a aceptar: MerkaERP exige verificación posterior del estado remoto.'),
      ]))),const SizedBox(height:12),
      if(rows.isEmpty)const Card(child:ListTile(title:Text('No hay liquidaciones disponibles.')))
      else for(final row in rows) Card(child:ListTile(
        leading:Icon(row['electronic_status']=='accepted'?Icons.verified:row['electronic_status']=='rejected'?Icons.error_outline:Icons.description_outlined),
        title:Text('${row['empleado']} · ${row['periodo']}'),
        subtitle:Text('Estado local: ${row['estado']} · Electrónico: ${row['electronic_status'] ?? 'sin preparar'}${row['external_id']==null?'':' · ID ${row['external_id']}'}'),
        trailing:Wrap(spacing:6,children:[
          if(row['electronic_status']==null||row['electronic_status']=='rejected') OutlinedButton(onPressed:()=>_run(()=>ElectronicPayrollService.instance.submit((row['id'] as num).toInt())),child:const Text('Transmitir')),
          if(row['electronic_status']=='submitted') FilledButton.tonal(onPressed:()=>_run(()=>ElectronicPayrollService.instance.verify((row['id'] as num).toInt())),child:const Text('Verificar')),
        ]),
      )),
    ]);
  });
}
