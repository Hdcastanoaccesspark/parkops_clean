import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../config.dart';
import '../theme/app_theme.dart';
import '../widgets/parkops_components.dart';
import '../widgets/status_timeline.dart'; // <-- NUEVO
import 'nueva_solicitud_screen.dart';

class ClienteDashboard extends StatefulWidget {
  const ClienteDashboard({super.key});
  @override
  ClienteDashboardState createState() => ClienteDashboardState();
}

class ClienteDashboardState extends State<ClienteDashboard> {
  String _nombre = '';
  String _parqueaderoNombre = '';
  int? _parqueaderoId;
  List<dynamic> _solicitudes = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _cargarSolicitudes();
  }

  Future<void> _loadUserData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _nombre = prefs.getString('nombre') ?? 'Cliente';
      _parqueaderoNombre = prefs.getString('parqueaderoNombre') ?? '';
      _parqueaderoId = prefs.getInt('parqueaderoId');
    });
  }

  Future<void> _cargarSolicitudes() async {
    setState(() => _isLoading = true);
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    if (token == null) {
      setState(() => _isLoading = false);
      return;
    }
    try {
      final res = await http.get(
        Uri.parse('$API_BASE_URL/api/solicitudes'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (res.statusCode == 200) {
        setState(() {
          _solicitudes = jsonDecode(res.body);
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
        _msg('Error al cargar solicitudes');
      }
    } catch (e) {
      setState(() => _isLoading = false);
      _msg('Error de conexión');
    }
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cerrar sesión'),
        content: const Text('¿Está seguro de que desea cerrar sesión?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sí'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
      if (mounted) Navigator.pushReplacementNamed(context, '/login');
    }
  }

  void _msg(String m, {bool err = true}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(m),
        backgroundColor: err ? Colors.red : Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.darkBackground,
      appBar: AppBar(
        title: const Text('ParkOps - Cliente'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: AppTheme.textPrimary),
            onPressed: _logout,
            tooltip: 'Cerrar sesión',
          ),
        ],
      ),
      body: Column(
        children: [
          // Header operacional
          ParkopsHeader(
            title: _parqueaderoNombre.isNotEmpty
                ? _parqueaderoNombre
                : 'Parqueadero',
            subtitle: 'Última atención: Hoy',
            trailing: const ParkopsStatusBadge(status: 'operativo'),
          ),
          const SizedBox(height: 16),
          // Botón principal grande
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: ParkopsAccentButton(
              label: 'REPORTAR NOVEDAD',
              icon: Icons.warning_amber_rounded,
              onPressed: () async {
                final ok = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const NuevaSolicitudScreen(),
                  ),
                );
                if (ok == true) _cargarSolicitudes();
              },
            ),
          ),
          const SizedBox(height: 24),
          // Lista de solicitudes
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Mis Solicitudes',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _solicitudes.isEmpty
                ? const Center(
                    child: Text(
                      'No tienes solicitudes aún.\nPresiona "REPORTAR NOVEDAD" para comenzar.',
                      style: TextStyle(color: AppTheme.textSecondary),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 24),
                    itemCount: _solicitudes.length,
                    itemBuilder: (_, i) {
                      final solicitud = _solicitudes[i];
                      return ParkopsCard(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 6,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    '#${solicitud['id']}',
                                    style: const TextStyle(
                                      color: AppTheme.textSecondary,
                                      fontSize: 12,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    solicitud['tipo'] ?? '',
                                    style: const TextStyle(
                                      color: AppTheme.textPrimary,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const Spacer(),
                                  ParkopsStatusBadge(
                                    status: solicitud['estado'] ?? 'pendiente',
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                solicitud['descripcion'] ?? '',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppTheme.textSecondary,
                                ),
                              ),
                              const SizedBox(height: 12),
                              StatusTimeline(
                                currentStatus:
                                    solicitud['estado'] ?? 'pendiente',
                              ),
                              if (solicitud['estado'] == 'finalizada')
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Align(
                                    alignment: Alignment.centerRight,
                                    child: TextButton.icon(
                                      icon: const Icon(
                                        Icons.download,
                                        size: 16,
                                        color: AppTheme.info,
                                      ),
                                      label: const Text(
                                        'PDF',
                                        style: TextStyle(color: AppTheme.info),
                                      ),
                                      onPressed: () {
                                        /* descargar pdf */
                                      },
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
