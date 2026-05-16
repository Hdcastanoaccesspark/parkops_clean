import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';
import '../config.dart';
import '../theme/app_theme.dart';
import '../widgets/parkops_components.dart';
import '../widgets/status_timeline.dart';
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
  List<dynamic> _reportesParqueadero = [];
  bool _isLoading = true;
  bool _isLoadingReportes = false;
  int _selectedTab = 0; // 0: Mis solicitudes, 1: Reportes del parqueadero

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

  // Cargar solicitudes propias (con timeline)
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
        final data = jsonDecode(res.body);
        setState(() {
          _solicitudes = data;
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

  // Cargar todos los reportes finalizados del parqueadero (historial)
  Future<void> _cargarReportesParqueadero() async {
    if (_parqueaderoId == null) return;
    setState(() => _isLoadingReportes = true);
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    if (token == null) {
      setState(() => _isLoadingReportes = false);
      return;
    }
    try {
      final res = await http.get(
        Uri.parse('$API_BASE_URL/parqueaderos/$_parqueaderoId/reportes'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (res.statusCode == 200) {
        setState(() {
          _reportesParqueadero = jsonDecode(res.body);
          _isLoadingReportes = false;
        });
      } else {
        setState(() => _isLoadingReportes = false);
        _msg('Error al cargar reportes del parqueadero');
      }
    } catch (e) {
      setState(() => _isLoadingReportes = false);
      _msg('Error de conexión');
    }
  }

  // Descarga de PDF (similar a técnico y coordinador)
  Future<void> _descargarPdf(int solicitudId) async {
    final url = '$API_BASE_URL/reporte/$solicitudId/pdf';
    final uri = Uri.parse(url);
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');
      if (token == null) throw Exception('No autenticado');
      _msg('Descargando PDF...', err: false);
      final response = await http.get(
        uri,
        headers: {'Authorization': 'Bearer $token'},
      );
      if (response.statusCode == 200) {
        final dir = await getTemporaryDirectory();
        final file = File('${dir.path}/reporte_$solicitudId.pdf');
        await file.writeAsBytes(response.bodyBytes);
        await OpenFile.open(file.path);
      } else {
        throw Exception('Error HTTP ${response.statusCode}');
      }
    } catch (e) {
      _msg('No se pudo descargar el PDF');
    }
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cerrar sesión'),
        content: const Text('¿Está seguro?'),
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
            icon: const Icon(Icons.person),
            onPressed: () => Navigator.pushNamed(context, '/perfil'),
            tooltip: 'Mi perfil',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              if (_selectedTab == 0)
                _cargarSolicitudes();
              else
                _cargarReportesParqueadero();
            },
            tooltip: 'Recargar',
          ),
          IconButton(icon: const Icon(Icons.logout), onPressed: _logout),
        ],
      ),
      body: Column(
        children: [
          ParkopsHeader(
            title: _parqueaderoNombre.isNotEmpty
                ? _parqueaderoNombre
                : 'Parqueadero',
            subtitle: 'Última atención: Hoy',
            trailing: const ParkopsStatusBadge(status: 'operativo'),
          ),
          const SizedBox(height: 16),
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
          const SizedBox(height: 16),
          // Pestañas
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: AppTheme.darkSurface,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                _buildTab('Mis Solicitudes', 0),
                _buildTab('Reportes del Parqueadero', 1),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _selectedTab == 0
                ? _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : _solicitudes.isEmpty
                      ? const Center(
                          child: Text(
                            'No tienes solicitudes aún.\nPresiona "REPORTAR NOVEDAD" para comenzar.',
                            style: TextStyle(color: AppTheme.textSecondary),
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _cargarSolicitudes,
                          child: ListView.builder(
                            padding: const EdgeInsets.only(bottom: 24),
                            itemCount: _solicitudes.length,
                            itemBuilder: (_, i) {
                              final solicitud = _solicitudes[i];
                              final estado = solicitud['estado'] ?? 'pendiente';
                              return ParkopsCard(
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 6,
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
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
                                          ParkopsStatusBadge(status: estado),
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
                                      StatusTimeline(currentStatus: estado),
                                      if (estado == 'finalizada')
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            top: 8,
                                          ),
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
                                                style: TextStyle(
                                                  color: AppTheme.info,
                                                ),
                                              ),
                                              onPressed: () => _descargarPdf(
                                                solicitud['id'],
                                              ),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        )
                : _isLoadingReportes
                ? const Center(child: CircularProgressIndicator())
                : _reportesParqueadero.isEmpty
                ? const Center(
                    child: Text(
                      'No hay reportes de mantenimiento para este parqueadero.',
                      style: TextStyle(color: AppTheme.textSecondary),
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _cargarReportesParqueadero,
                    child: ListView.builder(
                      padding: const EdgeInsets.only(bottom: 24),
                      itemCount: _reportesParqueadero.length,
                      itemBuilder: (_, i) {
                        final reporte = _reportesParqueadero[i];
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
                                      '#${reporte['id']}',
                                      style: const TextStyle(
                                        color: AppTheme.textSecondary,
                                        fontSize: 12,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      reporte['tipo'] ?? 'Mantenimiento',
                                      style: const TextStyle(
                                        color: AppTheme.textPrimary,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const Spacer(),
                                    ParkopsStatusBadge(status: 'finalizada'),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  reporte['descripcion'] ?? '',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: AppTheme.textSecondary,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Máquina: ${reporte['maquina_nombre']}',
                                  style: const TextStyle(
                                    color: AppTheme.info,
                                    fontSize: 12,
                                  ),
                                ),
                                if (reporte['fecha'] != null)
                                  Text(
                                    'Fecha: ${reporte['fecha'].toString().substring(0, 10)}',
                                    style: const TextStyle(
                                      color: AppTheme.textSecondary,
                                      fontSize: 12,
                                    ),
                                  ),
                                const SizedBox(height: 8),
                                Align(
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
                                    onPressed: () =>
                                        _descargarPdf(reporte['id']),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildTab(String label, int index) {
    final isSelected = _selectedTab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() => _selectedTab = index);
          if (index == 1 &&
              _reportesParqueadero.isEmpty &&
              _parqueaderoId != null) {
            _cargarReportesParqueadero();
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? AppTheme.primaryBlue : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: isSelected
                    ? AppTheme.textPrimary
                    : AppTheme.textSecondary,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
