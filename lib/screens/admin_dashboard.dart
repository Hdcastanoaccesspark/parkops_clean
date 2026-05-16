import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config.dart';
import '../theme/app_theme.dart';
import '../widgets/parkops_components.dart';
import 'todos_reportes_screen.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});
  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  List<dynamic> _solicitudes = [];
  List<dynamic> _tecnicos = [];
  bool _loading = true;
  String? _error;
  String _nombre = 'Coordinador';
  String _filtroEstado = 'todos';
  int _selectedTab = 0; // 0: Tickets, 1: Todos los reportes

  List<dynamic> get _solicitudesFiltradas {
    return _solicitudes.where((s) {
      return _filtroEstado == 'todos' || s['estado'] == _filtroEstado;
    }).toList();
  }

  int get _tecnicosActivos {
    if (_tecnicos.isEmpty) return 0;
    if (_tecnicos.first is Map && _tecnicos.first.containsKey('disponible')) {
      return _tecnicos.where((t) => t['disponible'] == true).length;
    }
    return _tecnicos.length;
  }

  int get _ticketsAbiertos => _solicitudes
      .where((s) => s['estado'] != 'finalizada' && s['estado'] != 'cancelada')
      .length;

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _cargarDatos();
  }

  Future<void> _loadUserData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _nombre = prefs.getString('nombre') ?? 'Coordinador';
    });
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
      if (resSol.statusCode == 200 && resTec.statusCode == 200) {
        setState(() {
          _solicitudes = jsonDecode(resSol.body);
          _tecnicos = jsonDecode(resTec.body);
          _loading = false;
        });
      } else {
        setState(() {
          _loading = false;
          _error =
              'Error al cargar datos (código ${resSol.statusCode} / ${resTec.statusCode})';
        });
      }
    } catch (e) {
      setState(() {
        _loading = false;
        _error = 'Error de conexión: ${e.toString()}';
      });
    }
  }

  Future<void> _asignarTecnico(dynamic solicitud) async {
    final tecnicoId = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Selecciona un técnico'),
        content: SizedBox(
          width: double.maxFinite,
          height: 300,
          child: ListView.builder(
            itemCount: _tecnicos.length,
            itemBuilder: (_, i) => ListTile(
              title: Text(_tecnicos[i]['nombre']),
              subtitle: Text(
                (_tecnicos[i]['disponible'] == true)
                    ? 'Disponible'
                    : 'No disponible',
              ),
              onTap: () => Navigator.pop(ctx, _tecnicos[i]['id']),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
        ],
      ),
    );
    if (tecnicoId == null) return;
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    final res = await http.put(
      Uri.parse('$API_BASE_URL/solicitudes/${solicitud['id']}/asignar'),
      headers: {'Authorization': 'Bearer $token'},
      body: {'tecnico_id': tecnicoId.toString()},
    );
    if (res.statusCode == 200) {
      _cargarDatos();
      _msg('Asignado correctamente');
    } else {
      _msg('Error al asignar');
    }
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
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
        ],
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
    } else {
      _msg('Error al reasignar');
    }
  }

  Future<void> _cancelarSolicitud(dynamic solicitud) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancelar solicitud'),
        content: const Text('¿Está seguro?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('No'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sí, cancelar'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    final res = await http.delete(
      Uri.parse('$API_BASE_URL/solicitudes/${solicitud['id']}'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (res.statusCode == 200) {
      _cargarDatos();
      _msg('Solicitud cancelada');
    } else {
      _msg('Error al cancelar');
    }
  }

  Future<void> _descargarPdf(int solicitudId) async {
    final url = '$API_BASE_URL/reporte/$solicitudId/pdf';
    final uri = Uri.parse(url);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        throw 'No se puede abrir';
      }
    } catch (e) {
      _msg('No se pudo abrir el PDF');
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
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Centro de Control',
              style: TextStyle(fontSize: 16, color: AppTheme.textPrimary),
            ),
            Text(
              _nombre,
              style: const TextStyle(
                fontSize: 12,
                color: AppTheme.textSecondary,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.person, color: AppTheme.textPrimary),
            onPressed: () => Navigator.pushNamed(context, '/perfil'),
            tooltip: 'Mi perfil',
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: AppTheme.textPrimary),
            onPressed: _cargarDatos,
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: AppTheme.textSecondary),
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
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  _error!,
                  style: const TextStyle(color: AppTheme.error),
                ),
              ),
            )
          : Column(
              children: [
                // KPIs
                SizedBox(
                  height: 100,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    children: [
                      _buildKpiCard(
                        'Técnicos activos',
                        '$_tecnicosActivos',
                        Icons.engineering,
                        AppTheme.info,
                      ),
                      _buildKpiCard(
                        'Tickets abiertos',
                        '$_ticketsAbiertos',
                        Icons.fact_check_outlined,
                        AppTheme.warning,
                      ),
                    ],
                  ),
                ),
                // Pestañas
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: AppTheme.darkSurface,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      _buildTab('Tickets', 0),
                      _buildTab('Todos los reportes', 1),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: _selectedTab == 0
                      ? Column(
                          children: [
                            // Filtros de estado
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              child: Row(
                                children: [
                                  _buildFilterChip('Todos', 'todos'),
                                  _buildFilterChip('Pendiente', 'pendiente'),
                                  _buildFilterChip('Asignada', 'asignada'),
                                  _buildFilterChip('En proceso', 'en_proceso'),
                                  _buildFilterChip('Finalizada', 'finalizada'),
                                ],
                              ),
                            ),
                            const SizedBox(height: 8),
                            Expanded(
                              child: _solicitudesFiltradas.isEmpty
                                  ? const Center(
                                      child: Text(
                                        'No hay tickets con ese filtro',
                                        style: TextStyle(
                                          color: AppTheme.textSecondary,
                                        ),
                                      ),
                                    )
                                  : RefreshIndicator(
                                      onRefresh: _cargarDatos,
                                      child: ListView.builder(
                                        padding: const EdgeInsets.only(
                                          bottom: 16,
                                        ),
                                        itemCount: _solicitudesFiltradas.length,
                                        itemBuilder: (_, i) {
                                          final s = _solicitudesFiltradas[i];
                                          return ParkopsCard(
                                            margin: const EdgeInsets.symmetric(
                                              horizontal: 16,
                                              vertical: 4,
                                            ),
                                            child: Padding(
                                              padding: const EdgeInsets.all(12),
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Row(
                                                    children: [
                                                      Expanded(
                                                        child: Text(
                                                          '#${s['id']} ${s['tipo']}',
                                                          style: const TextStyle(
                                                            color: AppTheme
                                                                .textPrimary,
                                                            fontWeight:
                                                                FontWeight.bold,
                                                          ),
                                                        ),
                                                      ),
                                                      ParkopsStatusBadge(
                                                        status:
                                                            s['estado'] ??
                                                            'pendiente',
                                                      ),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    s['descripcion'] ?? '',
                                                    maxLines: 2,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: const TextStyle(
                                                      color: AppTheme
                                                          .textSecondary,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 8),
                                                  Row(
                                                    mainAxisAlignment:
                                                        MainAxisAlignment.end,
                                                    children: [
                                                      if (s['estado'] ==
                                                              'pendiente' ||
                                                          s['estado'] ==
                                                              'asignada')
                                                        IconButton(
                                                          icon: const Icon(
                                                            Icons.person_add,
                                                            color:
                                                                AppTheme.info,
                                                            size: 20,
                                                          ),
                                                          onPressed: () =>
                                                              _asignarTecnico(
                                                                s,
                                                              ),
                                                        ),
                                                      if (s['estado'] !=
                                                              'finalizada' &&
                                                          s['estado'] !=
                                                              'cancelada')
                                                        IconButton(
                                                          icon: const Icon(
                                                            Icons.swap_horiz,
                                                            color: AppTheme
                                                                .warning,
                                                            size: 20,
                                                          ),
                                                          onPressed: () =>
                                                              _reasignarTecnico(
                                                                s,
                                                              ),
                                                        ),
                                                      if (s['estado'] !=
                                                              'finalizada' &&
                                                          s['estado'] !=
                                                              'cancelada')
                                                        IconButton(
                                                          icon: const Icon(
                                                            Icons.delete,
                                                            color:
                                                                AppTheme.error,
                                                            size: 20,
                                                          ),
                                                          onPressed: () =>
                                                              _cancelarSolicitud(
                                                                s,
                                                              ),
                                                        ),
                                                      if (s['estado'] ==
                                                          'finalizada')
                                                        IconButton(
                                                          icon: const Icon(
                                                            Icons.download,
                                                            color: AppTheme
                                                                .success,
                                                            size: 20,
                                                          ),
                                                          onPressed: () =>
                                                              _descargarPdf(
                                                                s['id'],
                                                              ),
                                                        ),
                                                    ],
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
                        )
                      : const TodosReportesScreen(), // Reutilizamos la pantalla de reportes ya creada
                ),
              ],
            ),
    );
  }

  Widget _buildKpiCard(String title, String value, IconData icon, Color color) {
    return Container(
      width: 150,
      margin: const EdgeInsets.only(right: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.darkSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.darkBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            title,
            style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, String estado) {
    final isSelected = _filtroEstado == estado;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        label: Text(label),
        selected: isSelected,
        onSelected: (_) => setState(() => _filtroEstado = estado),
        selectedColor: AppTheme.primaryBlue,
        backgroundColor: AppTheme.darkSurface,
        labelStyle: TextStyle(
          color: isSelected ? AppTheme.textPrimary : AppTheme.textSecondary,
          fontSize: 13,
        ),
        side: BorderSide(
          color: isSelected ? AppTheme.primaryBlue : AppTheme.darkBorder,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Widget _buildTab(String label, int index) {
    final isSelected = _selectedTab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedTab = index),
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
