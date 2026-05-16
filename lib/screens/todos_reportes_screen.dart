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

class TodosReportesScreen extends StatefulWidget {
  const TodosReportesScreen({super.key});
  @override
  State<TodosReportesScreen> createState() => _TodosReportesScreenState();
}

class _TodosReportesScreenState extends State<TodosReportesScreen> {
  List<dynamic> _reportes = [];
  bool _loading = true;
  String? _error;
  String _filtroParqueadero = 'todos';
  List<String> _parqueaderosUnicos = [];

  @override
  void initState() {
    super.initState();
    _cargarReportes();
  }

  Future<void> _cargarReportes() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    if (token == null) {
      setState(() {
        _error = 'No autenticado';
        _loading = false;
      });
      return;
    }
    try {
      final response = await http.get(
        Uri.parse('$API_BASE_URL/coordinador/todos_reportes'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as List;
        setState(() {
          _reportes = data;
          final parques = <String>{};
          for (var r in data) {
            if (r['parqueadero_nombre'] != null &&
                r['parqueadero_nombre'].isNotEmpty) {
              parques.add(r['parqueadero_nombre']);
            }
          }
          _parqueaderosUnicos = parques.toList()..sort();
          _loading = false;
        });
      } else {
        setState(() {
          _error = 'Error al cargar reportes (${response.statusCode})';
          _loading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Error de conexión: $e';
        _loading = false;
      });
    }
  }

  List<dynamic> get _reportesFiltrados {
    if (_filtroParqueadero == 'todos') return _reportes;
    return _reportes
        .where((r) => r['parqueadero_nombre'] == _filtroParqueadero)
        .toList();
  }

  Future<void> _descargarPdf(String pdfUrl) async {
    final url = '$API_BASE_URL$pdfUrl';
    final uri = Uri.parse(url);
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');
      if (token == null) {
        throw Exception('No autenticado');
      }
      _msg('Descargando PDF...', err: false);
      final response = await http.get(
        uri,
        headers: {'Authorization': 'Bearer $token'},
      );
      if (response.statusCode == 200) {
        final dir = await getTemporaryDirectory();
        final file = File('${dir.path}/reporte_${pdfUrl.split('/').last}.pdf');
        await file.writeAsBytes(response.bodyBytes);
        await OpenFile.open(file.path);
      } else {
        throw Exception('Error HTTP ${response.statusCode}');
      }
    } catch (e) {
      _msg('No se pudo descargar el PDF: $e');
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
        title: const Text('Todos los Reportes'),
        backgroundColor: AppTheme.darkSurface,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _cargarReportes,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(_error!, style: const TextStyle(color: AppTheme.error)),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _cargarReportes,
                    child: const Text('Reintentar'),
                  ),
                ],
              ),
            )
          : Column(
              children: [
                if (_parqueaderosUnicos.isNotEmpty)
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        _buildFiltroChip('Todos', 'todos'),
                        const SizedBox(width: 8),
                        ..._parqueaderosUnicos.map(
                          (p) => Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: _buildFiltroChip(p, p),
                          ),
                        ),
                      ],
                    ),
                  ),
                Expanded(
                  child: _reportesFiltrados.isEmpty
                      ? const Center(
                          child: Text(
                            'No hay reportes con ese filtro',
                            style: TextStyle(color: AppTheme.textSecondary),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _reportesFiltrados.length,
                          itemBuilder: (context, index) {
                            final r = _reportesFiltrados[index];
                            return ParkopsCard(
                              margin: const EdgeInsets.only(bottom: 12),
                              child: ListTile(
                                title: Text(
                                  '#${r['id']} - ${r['tipo']}',
                                  style: const TextStyle(
                                    color: AppTheme.textPrimary,
                                  ),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      r['descripcion'] ?? 'Sin descripción',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: AppTheme.textSecondary,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Parqueadero: ${r['parqueadero_nombre'] ?? 'No especificado'}',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: AppTheme.info,
                                      ),
                                    ),
                                    Text(
                                      'Técnico: ${r['tecnico_nombre']}',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: AppTheme.textSecondary,
                                      ),
                                    ),
                                    if (r['fecha_fin'] != null)
                                      Text(
                                        'Fecha: ${r['fecha_fin'].substring(0, 10)}',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: AppTheme.textSecondary,
                                        ),
                                      ),
                                  ],
                                ),
                                trailing: IconButton(
                                  icon: const Icon(
                                    Icons.picture_as_pdf,
                                    color: AppTheme.success,
                                  ),
                                  onPressed: () => _descargarPdf(r['pdf_url']),
                                ),
                                onTap: () => _descargarPdf(r['pdf_url']),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }

  Widget _buildFiltroChip(String label, String valor) {
    final isSelected = _filtroParqueadero == valor;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => setState(() => _filtroParqueadero = valor),
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
    );
  }
}
