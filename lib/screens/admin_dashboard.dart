import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../config.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});
  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  List<dynamic> _solicitudes = [], _tecnicos = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargarDatos();
  }

  Future<void> _cargarDatos() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    if (token == null) {
      setState(() {
        _loading = false;
        _error = 'Sin sesión';
      });
      return;
    }
    try {
      final resSol = await http.get(
        Uri.parse('$API_BASE_URL/api/solicitudes'),
        headers: {'Authorization': 'Bearer $token'},
      );
      final resTec = await http.get(
        Uri.parse('$API_BASE_URL/tecnicos'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (resSol.statusCode == 200 && resTec.statusCode == 200)
        setState(() {
          _solicitudes = jsonDecode(resSol.body);
          _tecnicos = jsonDecode(resTec.body);
          _loading = false;
        });
      else
        setState(() {
          _loading = false;
          _error = 'Error al cargar datos';
        });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = 'Error de conexión';
      });
    }
  }

  Future<void> _asignarTecnico(dynamic solicitud) async {
    /* igual que antes, llama a PUT /asignar */
  }
  Future<void> _reasignarTecnico(dynamic solicitud) async {
    final tecnicoId = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Selecciona nuevo técnico'),
        content: SizedBox(
          width: double.maxFinite,
          height: 300,
          child: ListView.builder(
            itemCount: _tecnicos.length,
            itemBuilder: (_, i) => ListTile(
              title: Text(_tecnicos[i]['nombre']),
              onTap: () => Navigator.pop(ctx, _tecnicos[i]['id']),
            ),
          ),
        ),
      ),
    );
    if (tecnicoId == null) return;
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    final res = await http.put(
      Uri.parse('$API_BASE_URL/solicitudes/${solicitud['id']}/reasignar'),
      headers: {'Authorization': 'Bearer $token'},
      body: {'nuevo_tecnico_id': tecnicoId.toString()},
    );
    if (res.statusCode == 200) {
      _cargarDatos();
      _msg('Reasignado correctamente');
    } else
      _msg('Error al reasignar');
  }

  Future<void> _cancelarSolicitud(dynamic solicitud) async {
    /* igual */
  }
  void _msg(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Panel de Administración'),
      backgroundColor: const Color(0xFF004A99),
      actions: [
        IconButton(icon: const Icon(Icons.refresh), onPressed: _cargarDatos),
        IconButton(
          icon: const Icon(Icons.logout),
          onPressed: () async {
            final prefs = await SharedPreferences.getInstance();
            await prefs.clear();
            if (mounted) Navigator.pushReplacementNamed(context, '/login');
          },
        ),
      ],
    ),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : _error != null
        ? Center(child: Text('Error: $_error'))
        : ListView.builder(
            itemCount: _solicitudes.length,
            itemBuilder: (_, i) {
              final s = _solicitudes[i];
              return Card(
                margin: const EdgeInsets.all(8),
                child: ListTile(
                  title: Text('${s['tipo']} - ${s['estado']}'),
                  subtitle: Text(
                    '${s['descripcion']}\nCliente: ${s['cliente_nombre'] ?? 'N/D'}',
                  ),
                  isThreeLine: true,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (s['estado'] == 'pendiente' ||
                          s['estado'] == 'asignada')
                        IconButton(
                          icon: const Icon(
                            Icons.person_add,
                            color: Colors.blue,
                          ),
                          onPressed: () => _asignarTecnico(s),
                        ),
                      if (s['estado'] != 'finalizada' &&
                          s['estado'] != 'cancelada')
                        IconButton(
                          icon: const Icon(
                            Icons.swap_horiz,
                            color: Colors.orange,
                          ),
                          onPressed: () => _reasignarTecnico(s),
                        ),
                      if (s['estado'] != 'finalizada' &&
                          s['estado'] != 'cancelada')
                        IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () => _cancelarSolicitud(s),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
  );
}
